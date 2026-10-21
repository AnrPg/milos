defmodule Palee.Infrastructure.Housekeeping.EctoHousekeepingStore do
  @moduledoc "Ecto adapter for the cleaning log (ADR-102)."

  @behaviour Palee.Housekeeping.Ports.HousekeepingStore

  import Ecto.Query

  alias Palee.Housekeeping.{Area, Entry}
  alias Palee.Repo

  @impl true
  def list_areas(%{organization_id: organization_id}, filters) do
    Area
    |> where([a], a.organization_id == ^organization_id)
    |> then(fn query ->
      if filters[:include_archived], do: query, else: where(query, [a], is_nil(a.archived_at))
    end)
    |> order_by([a], asc: a.name)
    |> Repo.all()
    |> Enum.map(&area_with_last_cleaning(organization_id, &1))
  end

  @impl true
  def get_area(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Area{} = area <-
           Area |> where([a], a.organization_id == ^organization_id and a.id == ^id) |> Repo.one() do
      normalize_area(area)
    else
      _missing -> nil
    end
  end

  @impl true
  def save_area(%{organization_id: organization_id}, nil, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Area.changeset()
    |> Repo.insert()
    |> result(&normalize_area/1)
  end

  def save_area(%{organization_id: organization_id}, id, attrs) do
    case Area
         |> where([a], a.organization_id == ^organization_id and a.id == ^id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      area -> area |> Area.changeset(attrs) |> Repo.update() |> result(&normalize_area/1)
    end
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
    |> order_by([e], desc: e.started_at)
    |> limit(^(filters[:limit] || 100))
    |> Repo.all()
    |> Enum.map(&normalize_entry/1)
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp since(query, nil), do: query
  defp since(query, %DateTime{} = from), do: where(query, [e], e.started_at >= ^from)

  defp area_with_last_cleaning(organization_id, area) do
    last =
      Entry
      |> where([e], e.organization_id == ^organization_id and e.area_id == ^area.id)
      |> where([e], not is_nil(e.finished_at))
      |> order_by([e], desc: e.finished_at)
      |> limit(1)
      |> Repo.one()

    area |> normalize_area() |> Map.put(:last_cleaned_at, last && last.finished_at)
  end

  defp normalize_area(area),
    do: Map.take(area, [:id, :name, :location_id, :tasks, :archived_at])

  defp normalize_entry(entry),
    do: Map.take(entry, [:id, :area_id, :user_id, :started_at, :finished_at, :tasks_done, :note])

  defp result({:ok, value}, normalize), do: {:ok, normalize.(value)}
  defp result(error, _normalize), do: error
end
