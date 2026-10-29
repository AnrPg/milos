defmodule Palee.Infrastructure.Fiscal.EctoTillSignatureStore do
  @moduledoc "Ecto adapter of the till signature store (ADR-251)."

  @behaviour Palee.Fiscal.Ports.TillSignatureStore

  import Ecto.Query

  alias Palee.Fiscal.{TillConnection, TillSignature, TillSignatureAttempt}
  alias Palee.Fiscal.Domain.TillSigningPolicy
  alias Palee.Repo

  @max_page 200

  # ── Connections ─────────────────────────────────────────────────────────

  @impl true
  def get_connection(%{organization_id: organization_id}, device) do
    TillConnection
    |> where([c], c.organization_id == ^organization_id and c.device == ^device)
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def save_connection(%{organization_id: organization_id}, device, attrs) do
    case Repo.one(
           from c in TillConnection,
             where: c.organization_id == ^organization_id and c.device == ^device
         ) do
      nil -> %TillConnection{organization_id: organization_id, device: device}
      connection -> connection
    end
    |> TillConnection.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, connection} -> {:ok, to_map(connection)}
      error -> error
    end
  end

  @impl true
  def set_connection_status(%{organization_id: organization_id}, device, status, error) do
    TillConnection
    |> where([c], c.organization_id == ^organization_id and c.device == ^device)
    |> Repo.update_all(set: [status: status, last_error: error, updated_at: DateTime.utc_now()])

    :ok
  end

  # ── Signatures ──────────────────────────────────────────────────────────

  @impl true
  def insert_signature(_context, attrs) do
    %TillSignature{}
    |> TillSignature.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, signature} -> {:ok, to_map(signature)}
      error -> error
    end
  end

  @impl true
  def get_signature(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        TillSignature
        |> where([s], s.organization_id == ^organization_id and s.id == ^id)
        |> Repo.one()
        |> to_map()

      :error ->
        nil
    end
  end

  @impl true
  def signatures_for_documents(_context, []), do: %{}

  def signatures_for_documents(%{organization_id: organization_id}, ids) do
    TillSignature
    |> where([s], s.organization_id == ^organization_id and s.document_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.document_id, to_map(&1)})
  end

  @impl true
  def claim(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    Repo.transaction(fn ->
      stale = DateTime.add(now, -TillSigningPolicy.claim_timeout_seconds(), :second)

      # A worker that died while signing may have reached the device: read
      # its row back instead of signing it again.
      TillSignature
      |> where([s], s.organization_id == ^organization_id)
      |> where([s], s.status == "sending" and s.claimed_at < ^stale)
      |> Repo.update_all(
        set: [status: "uncertain", next_attempt_at: now, last_error_code: "uncertain", updated_at: now]
      )

      to_sign =
        organization_id
        |> due(which, limit)
        |> where([s], s.status == "pending" and s.next_attempt_at <= ^now)

      {_count, signing} =
        TillSignature
        |> where([s], s.id in subquery(to_sign))
        |> select([s], s)
        |> Repo.update_all(
          set: [status: "sending", claimed_at: now, updated_at: now],
          inc: [attempts: 1]
        )

      to_read =
        organization_id
        |> due(which, limit)
        |> where([s], s.status == "uncertain" and s.next_attempt_at <= ^now)

      lease = DateTime.add(now, TillSigningPolicy.claim_timeout_seconds(), :second)

      {_count, reading} =
        TillSignature
        |> where([s], s.id in subquery(to_read))
        |> select([s], s)
        |> Repo.update_all(
          set: [claimed_at: now, next_attempt_at: lease, updated_at: now],
          inc: [attempts: 1]
        )

      Enum.map(signing ++ reading, &to_map/1)
    end)
    |> case do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  defp due(organization_id, which, limit) do
    TillSignature
    |> where([s], s.organization_id == ^organization_id)
    |> then(fn query ->
      case which do
        :due -> query
        id -> where(query, [s], s.id == ^id)
      end
    end)
    |> order_by([s], asc: s.next_attempt_at, asc: s.inserted_at)
    |> limit(^limit)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> select([s], s.id)
  end

  @impl true
  def finish(%{organization_id: organization_id}, id, changes, attempt) do
    Repo.transaction(fn ->
      with :ok <- insert_attempt(attempt, id),
           %TillSignature{} = signature <-
             Repo.one(
               from s in TillSignature,
                 where: s.organization_id == ^organization_id and s.id == ^id,
                 lock: "FOR UPDATE"
             ) || {:error, :not_found},
           {:ok, updated} <- signature |> TillSignature.changeset(changes) |> Repo.update() do
        to_map(updated)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_attempt(nil, _id), do: :ok

  defp insert_attempt(attempt, id) do
    case attempt
         |> Map.put(:signature_id, id)
         |> TillSignatureAttempt.insert_changeset()
         |> Repo.insert() do
      {:ok, _attempt} -> :ok
      error -> error
    end
  end

  @impl true
  def update_signature(context, id, changes), do: finish(context, id, changes, nil)

  @impl true
  def wake_waiting(%{organization_id: organization_id}, %DateTime{} = now) do
    {count, _rows} =
      TillSignature
      |> where([s], s.organization_id == ^organization_id and s.status in ["pending", "uncertain"])
      |> where([s], s.next_attempt_at > ^now)
      |> Repo.update_all(set: [next_attempt_at: now, updated_at: now])

    count
  end

  @impl true
  def list_signatures(%{organization_id: organization_id}, filters) do
    base = where(TillSignature, [s], s.organization_id == ^organization_id)

    query =
      base
      |> then(fn query ->
        case filters[:status] do
          nil -> query
          status -> where(query, [s], s.status == ^status)
        end
      end)
      |> then(fn query ->
        case filters[:device] do
          nil -> query
          device -> where(query, [s], s.device == ^device)
        end
      end)

    counts =
      base
      |> group_by([s], s.status)
      |> select([s], {s.status, count(s.id)})
      |> Repo.all()
      |> Map.new()

    %{
      signatures:
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
    TillSignatureAttempt
    |> where([a], a.organization_id == ^organization_id and a.signature_id == ^id)
    |> order_by([a], asc: a.started_at, asc: a.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  defp to_map(nil), do: nil
  defp to_map(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
end
