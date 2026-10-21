defmodule MilosTraining.Infrastructure.Partners.EctoPartnerStore do
  @moduledoc """
  Ecto adapter of the Partners store (ADR-169). Runs in a session of the
  club's gym; queries name the club and the people explicitly, the gym's
  tenant policy is the outer wall. A like and the match it may make are one
  transaction under an advisory lock on the pair, so two crossing likes
  make exactly one match.
  """

  @behaviour MilosTraining.Partners.Ports.PartnerStore

  import Ecto.Query

  alias MilosTraining.Partners.{Match, Message, Profile, Swipe}
  alias MilosTraining.Partners.Domain.MatchPolicy
  alias MilosTraining.Repo

  # Profiles.

  @impl true
  def get_profile(_context, club_id, user_id),
    do: Repo.get_by(Profile, club_id: club_id, user_id: user_id)

  @impl true
  def get_profile_by_id(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Profile, id)
      :error -> nil
    end
  end

  @impl true
  def list_profiles_of(_context, user_id) do
    Profile
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], asc: p.inserted_at)
    |> Repo.all()
  end

  @impl true
  def list_live_profiles(_context, _club_id, []), do: []

  def list_live_profiles(_context, club_id, user_ids) do
    Profile
    |> where([p], p.club_id == ^club_id and p.user_id in ^user_ids)
    |> where([p], p.active and is_nil(p.suspended_at))
    |> Repo.all()
  end

  @impl true
  def create_profile(_context, attrs), do: attrs |> Profile.create_changeset() |> Repo.insert()

  @impl true
  def update_profile(_context, %Profile{} = profile, changes),
    do: profile |> Profile.changeset(changes) |> Repo.update()

  @impl true
  def set_active_for_user(_context, user_id, active) do
    {count, _rows} =
      Profile
      |> where([p], p.user_id == ^user_id and is_nil(p.suspended_at) and p.active != ^active)
      |> Repo.update_all(set: [active: active, updated_at: DateTime.utc_now()])

    count
  end

  # Swipes.

  @impl true
  def list_swipes_by(_context, club_id, swiper_id) do
    Swipe
    |> where([s], s.club_id == ^club_id and s.swiper_id == ^swiper_id)
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
           reverse = get_swipe(attrs.club_id, attrs.target_id, attrs.swiper_id),
           {:ok, match, new?} <- maybe_match(mutual?.(reverse), attrs, pair, now) do
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
      conflict_target: [:club_id, :swiper_id, :target_id],
      returning: true
    )
    |> case do
      {:ok, swipe} -> {:ok, swipe}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_swipe}
    end
  end

  defp get_swipe(club_id, swiper_id, target_id),
    do: Repo.get_by(Swipe, club_id: club_id, swiper_id: swiper_id, target_id: target_id)

  defp maybe_match(false, _attrs, _pair, _now), do: {:ok, nil, false}

  defp maybe_match(true, attrs, {a, b}, now) do
    case active_between(a, b) do
      %Match{} = match ->
        {:ok, match, false}

      nil ->
        %{club_id: attrs.club_id, user_a_id: a, user_b_id: b, matched_at: now}
        |> Map.merge(Map.take(attrs, [:organization_id]))
        |> Match.create_changeset()
        |> Repo.insert()
        |> case do
          {:ok, match} -> {:ok, match, true}
          {:error, _changeset} -> {:error, :invalid_match}
        end
    end
  end

  @impl true
  def delete_swipe(_context, club_id, swiper_id, target_id) do
    {count, _rows} =
      Swipe
      |> where(
        [s],
        s.club_id == ^club_id and s.swiper_id == ^swiper_id and s.target_id == ^target_id
      )
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

  defp end_filter(query, %{club_id: club_id, user_id: user_id}),
    do:
      where(
        query,
        [m],
        m.club_id == ^club_id and (m.user_a_id == ^user_id or m.user_b_id == ^user_id)
      )

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

  defp advisory_lock(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [key])
end
