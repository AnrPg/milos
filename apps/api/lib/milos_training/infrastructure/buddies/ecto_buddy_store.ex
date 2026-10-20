defmodule MilosTraining.Infrastructure.Buddies.EctoBuddyStore do
  @moduledoc """
  Ecto adapter of the Buddies store (ADR-160). Queries name the people
  explicitly; row security (party and owner policies) is the second wall.
  Lookups across people call the migration's definer functions.
  """

  @behaviour MilosTraining.Buddies.Ports.BuddyStore

  import Ecto.Query

  alias MilosTraining.Buddies.{Delivery, Link, Reply, Settings, SummaryGrant, SupportRequest}
  alias MilosTraining.Repo

  @open ~w(pending active)

  # Links.

  @impl true
  def list_links(_context, user_id, ended_since) do
    Link
    |> where([l], l.user_id == ^user_id or l.buddy_user_id == ^user_id)
    |> where([l], l.status in @open or l.updated_at >= ^ended_since)
    |> order_by([l], asc: l.inserted_at, asc: l.id)
    |> Repo.all()
  end

  @impl true
  def get_link(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Link, id)
      :error -> nil
    end
  end

  @impl true
  def create_link(_context, attrs, guard) do
    Repo.transaction(fn ->
      advisory_lock("buddy_links", attrs.user_id)

      outgoing =
        Link
        |> where([l], l.user_id == ^attrs.user_id and l.status in @open)
        |> Repo.all()

      with :ok <- guard.(outgoing),
           {:ok, link} <- attrs |> Link.create_changeset() |> Repo.insert() do
        link
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset_error(changeset))
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :user_id) or Keyword.has_key?(errors, :buddy_user_id),
      do: :buddy_already_invited,
      else: :invalid_buddy_link
  end

  @impl true
  def update_link(_context, %Link{} = link, changes) do
    link |> Link.changeset(changes) |> Repo.update()
  end

  @impl true
  def expire_stale(_context, user_id, now) do
    {count, _rows} =
      Link
      |> where([l], l.user_id == ^user_id or l.buddy_user_id == ^user_id)
      |> where([l], l.status == "pending" and l.expires_at <= ^now)
      |> Repo.update_all(set: [status: "expired", updated_at: now])

    count
  end

  @impl true
  def active_links_as_requester(_context, user_id) do
    Link
    |> where([l], l.user_id == ^user_id and l.status == "active")
    |> order_by([l], asc: l.started_at)
    |> Repo.all()
  end

  @impl true
  def open_links_between(_context, a, b) do
    Link
    |> where([l], l.status in @open)
    |> where(
      [l],
      (l.user_id == ^a and l.buddy_user_id == ^b) or (l.user_id == ^b and l.buddy_user_id == ^a)
    )
    |> Repo.all()
  end

  @impl true
  def relation(_context, other_id) do
    case Ecto.UUID.dump(other_id || "") do
      {:ok, other} ->
        %{rows: [[relation]]} = Repo.query!("SELECT milos_buddy_relation($1)", [other])
        relation

      :error ->
        nil
    end
  end

  @impl true
  def candidates(_context, term, limit) do
    %{rows: rows} =
      Repo.query!("SELECT user_id, relation FROM milos_buddy_candidates($1, $2)", [term, limit])

    Enum.map(rows, fn [id, relation] -> %{user_id: Ecto.UUID.load!(id), relation: relation} end)
  end

  @impl true
  def invite_preview(token_hash, now) do
    %{rows: rows} =
      Repo.query!(
        "SELECT link_id, inviter_id, status, expires_at FROM milos_buddy_invite_preview($1, $2)",
        [token_hash, DateTime.to_naive(now)]
      )

    case rows do
      [[link_id, inviter_id, status, expires_at]] ->
        %{
          link_id: Ecto.UUID.load!(link_id),
          inviter_id: Ecto.UUID.load!(inviter_id),
          status: status,
          expires_at: expires_at && DateTime.from_naive!(expires_at, "Etc/UTC")
        }

      [] ->
        nil
    end
  end

  @impl true
  def claim_invite(_context, token_hash, now) do
    %{rows: [[id]]} =
      Repo.query!("SELECT milos_buddy_claim_invite($1, $2)", [token_hash, DateTime.to_naive(now)])

    id && Ecto.UUID.load!(id)
  end

  @impl true
  def quiet_hours(_context, buddy_id) do
    %{rows: rows} =
      Repo.query!("SELECT quiet_from, quiet_to, tz FROM milos_buddy_quiet_hours($1)", [
        Ecto.UUID.dump!(buddy_id)
      ])

    case rows do
      [[from, to, tz]] -> %{quiet_from: from, quiet_to: to, tz: tz}
      [] -> nil
    end
  end

  @impl true
  def shared_phone(_context, requester_id) do
    %{rows: [[phone]]} =
      Repo.query!("SELECT milos_buddy_shared_phone($1)", [Ecto.UUID.dump!(requester_id)])

    phone
  end

  @impl true
  def summary_requesters(limit) do
    %{rows: rows} =
      Repo.query!("SELECT user_id, tz FROM milos_buddy_summary_requesters($1)", [limit])

    Enum.map(rows, fn [id, tz] -> %{user_id: Ecto.UUID.load!(id), tz: tz} end)
  end

  # Settings.

  @impl true
  def get_settings(_context, user_id), do: Repo.get_by(Settings, user_id: user_id)

  @impl true
  def put_settings(_context, user_id, changes) do
    fields = Map.keys(changes)

    %Settings{user_id: user_id}
    |> Settings.changeset(changes)
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at | fields]},
      conflict_target: [:user_id],
      returning: true
    )
  end

  # Support requests.

  @impl true
  def create_request(_context, attrs, deliveries, guard, window_start) do
    Repo.transaction(fn ->
      advisory_lock("support_requests", attrs.user_id)

      sent =
        SupportRequest
        |> where([r], r.user_id == ^attrs.user_id and is_nil(r.undone_at))
        |> where([r], r.inserted_at >= ^window_start)
        |> select([r], count(r.id))
        |> Repo.one()

      with :ok <- guard.(sent),
           {:ok, request} <- attrs |> SupportRequest.create_changeset() |> Repo.insert() do
        rows =
          Enum.map(deliveries, fn delivery ->
            %{
              id: Ecto.UUID.generate(),
              request_id: request.id,
              user_id: request.user_id,
              buddy_user_id: delivery.buddy_user_id,
              delivered_silently: delivery.silent,
              inserted_at: request.inserted_at
            }
          end)

        {_count, _rows} = Repo.insert_all(Delivery, rows)
        request
      else
        {:error, %Ecto.Changeset{}} -> Repo.rollback(:invalid_message)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def count_requests_between(_context, user_id, from, to) do
    SupportRequest
    |> where([r], r.user_id == ^user_id and is_nil(r.undone_at))
    |> where([r], r.inserted_at >= ^from and r.inserted_at < ^to)
    |> select([r], count(r.id))
    |> Repo.one()
  end

  @impl true
  def get_request(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(SupportRequest, id)
      :error -> nil
    end
  end

  @impl true
  def list_requests(_context, user_id, :sent, limit) do
    SupportRequest
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_requests(_context, user_id, :received, limit) do
    SupportRequest
    |> join(:inner, [r], d in Delivery, on: d.request_id == r.id and d.buddy_user_id == ^user_id)
    |> where([r], not is_nil(r.delivered_at) and is_nil(r.undone_at))
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def list_deliveries(_context, []), do: []

  def list_deliveries(_context, request_ids) do
    Delivery
    |> where([d], d.request_id in ^request_ids)
    |> order_by([d], asc: d.inserted_at, asc: d.id)
    |> Repo.all()
  end

  @impl true
  def list_replies(_context, []), do: []

  def list_replies(_context, request_ids) do
    Reply
    |> where([r], r.request_id in ^request_ids)
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> Repo.all()
  end

  @impl true
  def undo_request(_context, id, now) do
    {count, _rows} =
      SupportRequest
      |> where([r], r.id == ^id and is_nil(r.undone_at) and is_nil(r.delivered_at))
      |> Repo.update_all(set: [undone_at: now])

    count
  end

  @impl true
  def mark_delivered(_context, id, now) do
    {count, _rows} =
      SupportRequest
      |> where([r], r.id == ^id and is_nil(r.undone_at) and is_nil(r.delivered_at))
      |> Repo.update_all(set: [delivered_at: now])

    count
  end

  @impl true
  def mark_nudged(_context, id, now) do
    {count, _rows} =
      SupportRequest
      |> where([r], r.id == ^id and is_nil(r.nudge_sent_at))
      |> Repo.update_all(set: [nudge_sent_at: now])

    count
  end

  @impl true
  def insert_reply(_context, attrs, now) do
    Repo.transaction(fn ->
      case attrs |> Reply.changeset() |> Repo.insert() do
        {:ok, reply} ->
          Delivery
          |> where([d], d.request_id == ^reply.request_id)
          |> where([d], d.buddy_user_id == ^reply.buddy_user_id and is_nil(d.replied_at))
          |> Repo.update_all(set: [replied_at: now])

          reply

        {:error, _changeset} ->
          Repo.rollback(:invalid_reply)
      end
    end)
  end

  # Coach summary grants.

  @impl true
  def list_summary_grants(_context, user_id) do
    SummaryGrant
    |> where([g], g.user_id == ^user_id)
    |> order_by([g], asc: g.granted_at)
    |> Repo.all()
  end

  @impl true
  def grant_summary(_context, user_id, scope, now) do
    active = fn ->
      SummaryGrant
      |> where([g], g.user_id == ^user_id and g.scope == ^scope and is_nil(g.withdrawn_at))
      |> Repo.one()
    end

    case active.() do
      %SummaryGrant{} = grant ->
        {:ok, grant}

      nil ->
        Repo.insert(%SummaryGrant{user_id: user_id, scope: scope, granted_at: now},
          on_conflict: :nothing,
          conflict_target: {:unsafe_fragment, "(user_id, scope) WHERE withdrawn_at IS NULL"}
        )

        # A concurrent grant may have won; either way one grant is active.
        {:ok, active.()}
    end
  end

  @impl true
  def withdraw_summary(_context, user_id, scope, now) do
    {count, _rows} =
      SummaryGrant
      |> where([g], g.user_id == ^user_id and g.scope == ^scope and is_nil(g.withdrawn_at))
      |> Repo.update_all(set: [withdrawn_at: now, updated_at: now])

    count
  end

  defp advisory_lock(namespace, user_id),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["#{namespace}:#{user_id}"])
end
