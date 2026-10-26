defmodule Palee.Infrastructure.Housekeeping.EctoHousekeepingStore do
  @moduledoc "Ecto adapter for the cleaning log (ADR-102) and cleaning schedule (ADR-202)."

  @behaviour Palee.Housekeeping.Ports.HousekeepingStore

  import Ecto.Query

  alias Palee.Housekeeping.{Entry, Schedule}
  alias Palee.Repo

  @impl true
  def last_cleaned(_context, []), do: %{}

  def last_cleaned(%{organization_id: organization_id}, area_ids) do
    Entry
    |> where([e], e.organization_id == ^organization_id and e.area_id in ^area_ids)
    |> where([e], not is_nil(e.finished_at))
    |> group_by([e], e.area_id)
    |> select([e], {e.area_id, max(e.finished_at)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def start_entry(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Entry.start_changeset()
    |> Repo.insert()
    |> result(&normalize_entry/1)
  end

  @impl true
  def get_entry(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Entry{} = entry <-
           Entry
           |> where([e], e.organization_id == ^organization_id and e.id == ^id)
           |> Repo.one() do
      normalize_entry(entry)
    else
      _missing -> nil
    end
  end

  @impl true
  def finish_entry(%{organization_id: organization_id}, id, attrs) do
    case Entry
         |> where([e], e.organization_id == ^organization_id and e.id == ^id)
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      entry ->
        entry |> Entry.finish_changeset(attrs) |> Repo.update() |> result(&normalize_entry/1)
    end
  end

  @impl true
  def list_entries(%{organization_id: organization_id}, filters) do
    Entry
    |> where([e], e.organization_id == ^organization_id)
    |> filter(:user_id, filters[:user_id])
    |> filter(:area_id, filters[:area_id])
    |> since(filters[:from])
    |> until(filters[:to])
    |> order_by([e], desc: e.started_at)
    |> limit(^(filters[:limit] || 100))
    |> Repo.all()
    |> Enum.map(&normalize_entry/1)
  end

  @impl true
  def list_schedules(%{organization_id: organization_id}) do
    Schedule
    |> where([s], s.organization_id == ^organization_id)
    |> Repo.all()
    |> Enum.map(&normalize_schedule/1)
  end

  @impl true
  def put_schedule(%{organization_id: organization_id}, space_id, attrs) do
    current =
      Schedule
      |> where([s], s.organization_id == ^organization_id and s.space_id == ^space_id)
      |> Repo.one()

    (current || %Schedule{organization_id: organization_id, space_id: space_id})
    |> Schedule.changeset(attrs)
    |> Repo.insert_or_update()
    |> result(&normalize_schedule/1)
  end

  @impl true
  def delete_schedule(%{organization_id: organization_id}, space_id) do
    Schedule
    |> where([s], s.organization_id == ^organization_id and s.space_id == ^space_id)
    |> Repo.delete_all()

    :ok
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp since(query, nil), do: query
  defp since(query, %DateTime{} = from), do: where(query, [e], e.started_at >= ^from)

  defp until(query, nil), do: query
  defp until(query, %DateTime{} = to), do: where(query, [e], e.started_at < ^to)

  defp normalize_entry(entry),
    do: Map.take(entry, [:id, :area_id, :user_id, :started_at, :finished_at, :tasks_done, :note])

  defp normalize_schedule(schedule),
    do: Map.take(schedule, [:id, :space_id, :weekdays, :times, :comment])

  defp result({:ok, value}, normalize), do: {:ok, normalize.(value)}
  defp result(error, _normalize), do: error
end
