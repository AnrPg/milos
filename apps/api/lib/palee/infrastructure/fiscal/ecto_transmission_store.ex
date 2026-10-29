defmodule Palee.Infrastructure.Fiscal.EctoTransmissionStore do
  @moduledoc "Ecto adapter of the transmission store (ADR-243)."

  @behaviour Palee.Fiscal.Ports.TransmissionStore

  import Ecto.Query

  alias Palee.Fiscal.{AuthorityConnection, Transmission, TransmissionAttempt}
  alias Palee.Fiscal.Domain.TransmissionPolicy
  alias Palee.Repo

  @max_page 200

  # ── Connections ─────────────────────────────────────────────────────────

  @impl true
  def get_connection(%{organization_id: organization_id}, authority) do
    AuthorityConnection
    |> where([c], c.organization_id == ^organization_id and c.authority == ^authority)
    |> Repo.one()
    |> connection_map()
  end

  @impl true
  def save_connection(%{organization_id: organization_id}, authority, attrs) do
    case Repo.one(
           from c in AuthorityConnection,
             where: c.organization_id == ^organization_id and c.authority == ^authority
         ) do
      nil -> %AuthorityConnection{organization_id: organization_id, authority: authority}
      connection -> connection
    end
    |> AuthorityConnection.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, connection} -> {:ok, connection_map(connection)}
      error -> error
    end
  end

  @impl true
  def set_connection_status(%{organization_id: organization_id}, authority, status, error) do
    AuthorityConnection
    |> where([c], c.organization_id == ^organization_id and c.authority == ^authority)
    |> Repo.update_all(set: [status: status, last_error: error, updated_at: now()])

    :ok
  end

  defp connection_map(nil), do: nil

  defp connection_map(%AuthorityConnection{} = connection),
    do: connection |> Map.from_struct() |> Map.drop([:__meta__])

  # ── Transmissions ───────────────────────────────────────────────────────

  @impl true
  def insert_transmission(_context, attrs) do
    %Transmission{}
    |> Transmission.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, transmission} -> {:ok, transmission_map(transmission)}
      error -> error
    end
  end

  @impl true
  def get_transmission(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Transmission
      |> where([t], t.organization_id == ^organization_id and t.id == ^id)
      |> Repo.one()
      |> transmission_map()
    else
      :error -> nil
    end
  end

  @impl true
  def transmissions_for_documents(_context, []), do: %{}

  def transmissions_for_documents(%{organization_id: organization_id}, ids) do
    Transmission
    |> where([t], t.organization_id == ^organization_id and t.document_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.document_id, transmission_map(&1)})
  end

  @impl true
  def claim(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    stale = DateTime.add(now, -TransmissionPolicy.claim_timeout_seconds(), :second)

    candidates =
      Transmission
      |> where([t], t.organization_id == ^organization_id)
      |> where(
        [t],
        (t.status == "pending" and t.next_attempt_at <= ^now) or
          (t.status == "sending" and t.claimed_at < ^stale)
      )
      |> then(fn query ->
        case which do
          :due -> query
          id -> where(query, [t], t.id == ^id)
        end
      end)
      |> order_by([t], asc: t.next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([t], t.id)

    {_count, rows} =
      Transmission
      |> where([t], t.id in subquery(candidates))
      |> select([t], t)
      |> Repo.update_all(
        set: [status: "sending", claimed_at: now, updated_at: now()],
        inc: [attempts: 1]
      )

    Enum.map(rows, &transmission_map/1)
  end

  @impl true
  def finish(%{organization_id: organization_id}, id, changes, attempt) do
    Repo.transaction(fn ->
      with :ok <- insert_attempt(attempt, id),
           %Transmission{} = transmission <-
             Repo.one(
               from t in Transmission,
                 where: t.organization_id == ^organization_id and t.id == ^id,
                 lock: "FOR UPDATE"
             ) || {:error, :not_found},
           {:ok, updated} <- transmission |> Transmission.changeset(changes) |> Repo.update() do
        transmission_map(updated)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_attempt(nil, _id), do: :ok

  defp insert_attempt(attempt, id) do
    case attempt
         |> Map.put(:transmission_id, id)
         |> TransmissionAttempt.insert_changeset()
         |> Repo.insert() do
      {:ok, _attempt} -> :ok
      error -> error
    end
  end

  @impl true
  def update_transmission(context, id, changes), do: finish(context, id, changes, nil)

  @impl true
  def wake_waiting(%{organization_id: organization_id}, %DateTime{} = now) do
    {count, _rows} =
      Transmission
      |> where([t], t.organization_id == ^organization_id and t.status == "pending")
      |> where([t], t.next_attempt_at > ^now)
      |> Repo.update_all(set: [next_attempt_at: now, updated_at: now()])

    count
  end

  @impl true
  def list_transmissions(%{organization_id: organization_id}, filters) do
    base = where(Transmission, [t], t.organization_id == ^organization_id)

    query =
      case filters[:status] do
        nil -> base
        status -> where(base, [t], t.status == ^status)
      end

    limit = min(filters[:limit] || 50, @max_page)

    counts =
      base
      |> group_by([t], t.status)
      |> select([t], {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    %{
      transmissions:
        query
        |> order_by([t], desc: t.inserted_at, desc: t.id)
        |> limit(^limit)
        |> offset(^(filters[:offset] || 0))
        |> Repo.all()
        |> Enum.map(&transmission_map/1),
      total: Repo.aggregate(query, :count),
      counts: counts
    }
  end

  @impl true
  def list_attempts(%{organization_id: organization_id}, id) do
    TransmissionAttempt
    |> where([a], a.organization_id == ^organization_id and a.transmission_id == ^id)
    |> order_by([a], asc: a.started_at)
    |> Repo.all()
    |> Enum.map(&(&1 |> Map.from_struct() |> Map.drop([:__meta__])))
  end

  defp transmission_map(nil), do: nil

  defp transmission_map(%Transmission{} = transmission),
    do: transmission |> Map.from_struct() |> Map.drop([:__meta__])

  defp now, do: DateTime.utc_now()
end
