defmodule Palee.Infrastructure.Partners.EctoPartnerStore do
  @moduledoc """
  Ecto adapter of the Partners store (ADR-169, ADR-280). Runs in the acting
  person's own session; queries name the people explicitly and row security
  is the outer wall. A like and the match it may make are one transaction
  under an advisory lock on the pair, so two crossing likes make exactly one
  match.
  """

  @behaviour Palee.Partners.Ports.PartnerStore

  import Ecto.Query

  alias Palee.Partners.{Match, Message, Profile, Report, Swipe}
  alias Palee.Partners.Domain.MatchPolicy
  alias Palee.Repo

  # Profiles.

  @impl true
  def get_profile(_context, user_id), do: Repo.get_by(Profile, user_id: user_id)

  @impl true
  def get_profiles(_context, user_ids) do
    Profile
    |> where([p], p.user_id in ^Enum.uniq(user_ids))
    |> Repo.all()
  end

  @impl true
  def list_live_profiles(_context, excluded_ids) do
    Profile
    |> where([p], p.active and is_nil(p.paused_at))
    |> where([p], p.user_id not in ^Enum.uniq(excluded_ids))
    |> Repo.all()
  end

  @impl true
  def create_profile(_context, attrs), do: attrs |> Profile.create_changeset() |> Repo.insert()

  @impl true
  def update_profile(_context, %Profile{} = profile, changes),
    do: profile |> Profile.changeset(changes) |> Repo.update()

  # Swipes.

  @impl true
  def list_swipes_by(_context, swiper_id) do
    Swipe
    |> where([s], s.swiper_id == ^swiper_id)
    |> Repo.all()
  end

  @impl true
  def count_swipes_since(_context, swiper_id, since) do
    Swipe
    |> where([s], s.swiper_id == ^swiper_id and s.updated_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def record_swipe(_context, attrs, mutual?, now) do
    pair = MatchPolicy.pair(attrs.swiper_id, attrs.target_id)

    Repo.transaction(fn ->
      advisory_lock(MatchPolicy.pair_key(pair))

      with {:ok, swipe} <- upsert_swipe(attrs, now),
           reverse = get_swipe(attrs.target_id, attrs.swiper_id),
           {:ok, match, new?} <- maybe_match(mutual?.(reverse), pair, now) do
        %{swipe: swipe, match: match, new_match: new?}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp upsert_swipe(attrs, now) do
    attrs
    |> Swipe.changeset()
    |> Ecto.Changeset.force_change(:inserted_at, now)
    |> Ecto.Changeset.force_change(:updated_at, now)
    |> Repo.insert(
      on_conflict: [set: [direction: attrs.direction, updated_at: now]],
      conflict_target: [:swiper_id, :target_id],
      returning: true
    )
    |> case do
      {:ok, swipe} -> {:ok, swipe}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_swipe}
    end
  end

  defp get_swipe(swiper_id, target_id),
    do: Repo.get_by(Swipe, swiper_id: swiper_id, target_id: target_id)

  defp maybe_match(false, _pair, _now), do: {:ok, nil, false}

  defp maybe_match(true, {a, b}, now) do
    case active_between(a, b) do
      %Match{} = match ->
        {:ok, match, false}

      nil ->
        %{user_a_id: a, user_b_id: b, matched_at: now}
        |> Match.create_changeset()
        |> Repo.insert()
        |> case do
          {:ok, match} -> {:ok, match, true}
          {:error, _changeset} -> {:error, :invalid_match}
        end
    end
  end

  @impl true
  def delete_swipe(_context, swiper_id, target_id) do
    {count, _rows} =
      Swipe
      |> where([s], s.swiper_id == ^swiper_id and s.target_id == ^target_id)
      |> Repo.delete_all()

    count
  end

  # Matches.

  @impl true
  def get_match(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Match, id)
      :error -> nil
    end
  end

  @impl true
  def list_matches(_context, user_id) do
    Match
    |> where([m], m.user_a_id == ^user_id or m.user_b_id == ^user_id)
    |> order_by([m], desc: coalesce(m.last_message_at, m.matched_at), desc: m.id)
    |> Repo.all()
  end

  @impl true
  def active_match_between(_context, a, b) do
    {a, b} = MatchPolicy.pair(a, b)
    active_between(a, b)
  end

  defp active_between(a, b) do
    Match
    |> where([m], m.user_a_id == ^a and m.user_b_id == ^b and m.status == "active")
    |> Repo.one()
  end

  @impl true
  def active_partner_ids(_context, user_id) do
    Match
    |> where([m], m.status == "active" and (m.user_a_id == ^user_id or m.user_b_id == ^user_id))
    |> select(
      [m],
      fragment(
        "CASE WHEN ? = ? THEN ? ELSE ? END",
        m.user_a_id,
        type(^user_id, :binary_id),
        m.user_b_id,
        m.user_a_id
      )
    )
    |> Repo.all()
  end

  @impl true
  def update_match(_context, %Match{} = match, changes),
    do: match |> Match.changeset(changes) |> Repo.update()

  @impl true
  def end_matches(_context, filter, changes) do
    Match
    |> where([m], m.status == "active")
    |> end_filter(filter)
    |> Repo.all()
    |> Enum.flat_map(fn match ->
      case match |> Match.changeset(changes) |> Repo.update() do
        {:ok, ended} -> [ended]
        {:error, _changeset} -> []
      end
    end)
  end

  defp end_filter(query, %{pair: {a, b}}) do
    {a, b} = MatchPolicy.pair(a, b)
    where(query, [m], m.user_a_id == ^a and m.user_b_id == ^b)
  end

  defp end_filter(query, %{user_id: user_id}),
    do: where(query, [m], m.user_a_id == ^user_id or m.user_b_id == ^user_id)

  defp end_filter(query, _filter), do: where(query, [m], false)

  # Messages.

  @impl true
  def list_messages(_context, match_id, cursor, limit) do
    Message
    |> where([m], m.match_id == ^match_id)
    |> before_cursor(cursor)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp before_cursor(query, nil), do: query

  defp before_cursor(query, %{inserted_at: at, id: id}),
    do: where(query, [m], m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id))

  @impl true
  def insert_message(_context, attrs, now) do
    Repo.transaction(fn ->
      changeset = attrs |> Message.changeset() |> Ecto.Changeset.force_change(:inserted_at, now)

      with {:ok, message} <- Repo.insert(changeset) do
        Match
        |> where([m], m.id == ^message.match_id)
        |> Repo.update_all(set: [last_message_at: now, updated_at: now])

        message
      else
        {:error, _changeset} -> Repo.rollback(:invalid_partner_message)
      end
    end)
  end

  @impl true
  def unread_counts(_context, _user_id, []), do: %{}

  def unread_counts(_context, user_id, matches) do
    matches
    |> Enum.map(fn match -> {match.id, MatchPolicy.read_at(match, user_id)} end)
    |> Enum.reduce(dynamic(false), fn
      {id, nil}, acc -> dynamic([m], ^acc or m.match_id == ^id)
      {id, read_at}, acc -> dynamic([m], ^acc or (m.match_id == ^id and m.inserted_at > ^read_at))
    end)
    |> then(fn condition ->
      Message
      |> where([m], m.author_id != ^user_id)
      |> where(^condition)
      |> group_by([m], m.match_id)
      |> select([m], {m.match_id, count(m.id)})
      |> Repo.all()
      |> Map.new()
    end)
  end

  # Reports.

  @impl true
  def insert_report(_context, attrs) do
    attrs
    |> Report.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, report} ->
        {:ok, report}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :reporter_id),
          do: {:ok, :already_reported},
          else: {:error, changeset}
    end
  end

  @impl true
  def get_report(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Report, id)
      :error -> nil
    end
  end

  @impl true
  def list_reports(_context, status) do
    Report
    |> where([r], r.status == ^status)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(500)
    |> Repo.all()
  end

  @impl true
  def decide_reports(_context, target_id, changes) do
    Report
    |> where([r], r.target_id == ^target_id and r.status == "open")
    |> Repo.all()
    |> Enum.flat_map(fn report ->
      case report |> Report.decision_changeset(changes) |> Repo.update() do
        {:ok, decided} -> [decided]
        {:error, _changeset} -> []
      end
    end)
  end

  defp advisory_lock(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [key])
end
