defmodule Palee.Infrastructure.Fiscal.EctoEInvoiceStore do
  @moduledoc "Ecto adapter of the e-invoice store (ADR-250)."

  @behaviour Palee.Fiscal.Ports.EInvoiceStore

  import Ecto.Query

  alias Palee.Fiscal.{EInvoiceAttempt, EInvoiceSubmission, NetworkConnection}
  alias Palee.Fiscal.Domain.EInvoicePolicy
  alias Palee.Infrastructure.Fiscal.ConnectionCheckFields
  alias Palee.Repo

  @max_page 200

  # ── Connections ─────────────────────────────────────────────────────────

  @impl true
  def get_connection(%{organization_id: organization_id}, network) do
    NetworkConnection
    |> where([c], c.organization_id == ^organization_id and c.network == ^network)
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def save_connection(%{organization_id: organization_id}, network, attrs) do
    case Repo.one(
           from c in NetworkConnection,
             where: c.organization_id == ^organization_id and c.network == ^network
         ) do
      nil -> %NetworkConnection{organization_id: organization_id, network: network}
      connection -> connection
    end
    |> NetworkConnection.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, connection} -> {:ok, to_map(connection)}
      error -> error
    end
  end

  @impl true
  def set_connection_status(%{organization_id: organization_id}, network, status, error) do
    NetworkConnection
    |> where([c], c.organization_id == ^organization_id and c.network == ^network)
    |> Repo.update_all(set: [status: status, last_error: error, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def update_connection_check(%{organization_id: organization_id}, network, attrs) do
    NetworkConnection
    |> where([c], c.organization_id == ^organization_id and c.network == ^network)
    |> Repo.update_all(set: ConnectionCheckFields.set(attrs))

    :ok
  end

  # ── Submissions ─────────────────────────────────────────────────────────

  @impl true
  def insert_submission(_context, attrs) do
    %EInvoiceSubmission{}
    |> EInvoiceSubmission.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, submission} -> {:ok, to_map(submission)}
      error -> error
    end
  end

  @impl true
  def get_submission(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        EInvoiceSubmission
        |> where([s], s.organization_id == ^organization_id and s.id == ^id)
        |> Repo.one()
        |> to_map()

      :error ->
        nil
    end
  end

  @impl true
  def submissions_for_documents(_context, []), do: %{}

  def submissions_for_documents(%{organization_id: organization_id}, ids) do
    EInvoiceSubmission
    |> where([s], s.organization_id == ^organization_id and s.document_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.document_id, to_map(&1)})
  end

  @impl true
  def claim(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    Repo.transaction(fn ->
      stale = DateTime.add(now, -EInvoicePolicy.claim_timeout_seconds(), :second)

      # A worker that died while sending may have reached the access point:
      # its row becomes uncertain and is never sent again by itself.
      EInvoiceSubmission
      |> where([s], s.organization_id == ^organization_id)
      |> where([s], s.status == "sending" and s.claimed_at < ^stale)
      |> Repo.update_all(
        set: [
          status: "uncertain",
          next_attempt_at: nil,
          last_error_code: "uncertain",
          last_error_message: "worker_lost",
          updated_at: now
        ]
      )

      to_send =
        organization_id
        |> due(which, limit)
        |> where([s], s.status == "pending" and s.next_attempt_at <= ^now)

      {_count, sending} =
        EInvoiceSubmission
        |> where([s], s.id in subquery(to_send))
        |> select([s], s)
        |> Repo.update_all(
          set: [status: "sending", claimed_at: now, updated_at: now],
          inc: [attempts: 1]
        )

      # A delivery poll keeps the row `submitted` and pushes its due time
      # past the lease, so a dead worker's poll simply runs again later.
      to_poll =
        organization_id
        |> due(which, limit)
        |> where([s], s.status == "submitted" and s.next_attempt_at <= ^now)

      lease = DateTime.add(now, EInvoicePolicy.claim_timeout_seconds(), :second)

      {_count, polling} =
        EInvoiceSubmission
        |> where([s], s.id in subquery(to_poll))
        |> select([s], s)
        |> Repo.update_all(set: [claimed_at: now, next_attempt_at: lease, updated_at: now])

      Enum.map(sending ++ polling, &to_map/1)
    end)
    |> case do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  defp due(organization_id, which, limit) do
    EInvoiceSubmission
    |> where([s], s.organization_id == ^organization_id)
    |> then(fn query ->
      case which do
        :due -> query
        id -> where(query, [s], s.id == ^id)
      end
    end)
    |> order_by([s], asc: s.next_attempt_at)
    |> limit(^limit)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> select([s], s.id)
  end

  @impl true
  def finish(%{organization_id: organization_id}, id, changes, attempt) do
    Repo.transaction(fn ->
      with :ok <- insert_attempt(attempt, id),
           %EInvoiceSubmission{} = submission <-
             Repo.one(
               from s in EInvoiceSubmission,
                 where: s.organization_id == ^organization_id and s.id == ^id,
                 lock: "FOR UPDATE"
             ) || {:error, :not_found},
           {:ok, updated} <- submission |> EInvoiceSubmission.changeset(changes) |> Repo.update() do
        to_map(updated)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_attempt(nil, _id), do: :ok

  defp insert_attempt(attempt, id) do
    case attempt
         |> Map.put(:submission_id, id)
         |> EInvoiceAttempt.insert_changeset()
         |> Repo.insert() do
      {:ok, _attempt} -> :ok
      error -> error
    end
  end

  @impl true
  def update_submission(context, id, changes), do: finish(context, id, changes, nil)

  @impl true
  def wake_waiting(%{organization_id: organization_id}, %DateTime{} = now) do
    {count, _rows} =
      EInvoiceSubmission
      |> where([s], s.organization_id == ^organization_id and s.status == "pending")
      |> where([s], s.next_attempt_at > ^now)
      |> Repo.update_all(set: [next_attempt_at: now, updated_at: now])

    count
  end

  @impl true
  def wake_submitted(%{organization_id: organization_id}, provider_id, %DateTime{} = now) do
    {count, _rows} =
      EInvoiceSubmission
      |> where([s], s.organization_id == ^organization_id and s.status == "submitted")
      |> where([s], s.provider_submission_id == ^provider_id)
      |> Repo.update_all(set: [next_attempt_at: now, updated_at: now])

    count
  end

  @impl true
  def list_submissions(%{organization_id: organization_id}, filters) do
    base = where(EInvoiceSubmission, [s], s.organization_id == ^organization_id)

    query =
      case filters[:status] do
        nil -> base
        status -> where(base, [s], s.status == ^status)
      end

    counts =
      base
      |> group_by([s], s.status)
      |> select([s], {s.status, count(s.id)})
      |> Repo.all()
      |> Map.new()

    %{
      submissions:
        query
        |> order_by([s], desc: s.inserted_at, desc: s.id)
        |> limit(^min(filters[:limit] || 50, @max_page))
        |> offset(^(filters[:offset] || 0))
        |> Repo.all()
        |> Enum.map(&to_map/1),
      total: Repo.aggregate(query, :count),
      counts: counts
    }
  end

  @impl true
  def list_attempts(%{organization_id: organization_id}, id) do
    EInvoiceAttempt
    |> where([a], a.organization_id == ^organization_id and a.submission_id == ^id)
    |> order_by([a], asc: a.started_at, asc: a.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  defp to_map(nil), do: nil
  defp to_map(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
end
