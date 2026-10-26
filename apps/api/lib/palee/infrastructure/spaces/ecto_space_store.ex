defmodule Palee.Infrastructure.Spaces.EctoSpaceStore do
  @moduledoc "Ecto adapter for spaces, floor plans and unavailability (ADR-202)."

  @behaviour Palee.Spaces.Ports.SpaceStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Spaces.{FloorPlan, Space, Unavailability}

  @space_fields [
    :id,
    :name,
    :description,
    :directions,
    :location_id,
    :tasks,
    :floor_plan_id,
    :area,
    :archived_at
  ]

  @impl true
  def list_spaces(%{organization_id: organization_id}, filters) do
    Space
    |> where([s], s.organization_id == ^organization_id)
    |> then(fn query ->
      if filters[:include_archived], do: query, else: where(query, [s], is_nil(s.archived_at))
    end)
    |> then(fn query ->
      case filters[:ids] do
        nil -> query
        ids -> where(query, [s], s.id in ^Enum.flat_map(ids, &cast_ids/1))
      end
    end)
    |> then(fn query ->
      if Map.has_key?(filters, :location_id),
        do: by_location(query, filters[:location_id]),
        else: query
    end)
    |> order_by([s], asc: s.name)
    |> Repo.all()
    |> Enum.map(&normalize_space/1)
  end

  defp by_location(query, nil), do: where(query, [s], is_nil(s.location_id))
  defp by_location(query, id), do: where(query, [s], s.location_id == ^id)

  @impl true
  def get_space(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Space{} = space <-
           Space
           |> where([s], s.organization_id == ^organization_id and s.id == ^id)
           |> Repo.one() do
      normalize_space(space)
    else
      _missing -> nil
    end
  end

  @impl true
  def save_space(%{organization_id: organization_id}, nil, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Space.changeset()
    |> Repo.insert()
    |> result(&normalize_space/1)
  end

  def save_space(%{organization_id: organization_id}, id, attrs) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Space{} = space <-
           Space
           |> where([s], s.organization_id == ^organization_id and s.id == ^id)
           |> Repo.one() do
      space |> Space.changeset(attrs) |> Repo.update() |> result(&normalize_space/1)
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def list_floor_plans(%{organization_id: organization_id}, filters) do
    FloorPlan
    |> where([p], p.organization_id == ^organization_id)
    |> then(fn query ->
      case Map.fetch(filters, :location_id) do
        {:ok, nil} -> where(query, [p], is_nil(p.location_id))
        {:ok, id} -> where(query, [p], p.location_id == ^id)
        :error -> query
      end
    end)
    |> order_by([p], asc: p.sort_order, asc: p.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_plan/1)
  end

  @impl true
  def get_floor_plan(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %FloorPlan{} = plan <-
           FloorPlan
           |> where([p], p.organization_id == ^organization_id and p.id == ^id)
           |> Repo.one() do
      normalize_plan(plan)
    else
      _missing -> nil
    end
  end

  @impl true
  def save_floor_plan(%{organization_id: organization_id}, nil, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> FloorPlan.create_changeset()
    |> Repo.insert()
    |> result(&normalize_plan/1)
  end

  def save_floor_plan(%{organization_id: organization_id}, id, attrs) do
    case FloorPlan
         |> where([p], p.organization_id == ^organization_id and p.id == ^id)
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      plan ->
        plan |> FloorPlan.update_changeset(attrs) |> Repo.update() |> result(&normalize_plan/1)
    end
  end

  # The spaces drawn on it lose their area too: it was drawn on this image.
  @impl true
  def delete_floor_plan(%{organization_id: organization_id}, id) do
    case FloorPlan
         |> where([p], p.organization_id == ^organization_id and p.id == ^id)
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      plan ->
        Repo.transaction(fn ->
          Space
          |> where([s], s.organization_id == ^organization_id and s.floor_plan_id == ^plan.id)
          |> Repo.update_all(set: [floor_plan_id: nil, area: nil])

          plan |> Repo.delete!() |> normalize_plan()
        end)
    end
  end

  @impl true
  def list_unavailabilities(%{organization_id: organization_id}, space_ids, %DateTime{} = from) do
    Unavailability
    |> where([u], u.organization_id == ^organization_id and u.space_id in ^space_ids)
    |> where([u], u.ends_at > ^from)
    |> order_by([u], asc: u.starts_at)
    |> Repo.all()
    |> Enum.map(&normalize_window/1)
  end

  @impl true
  def create_unavailability(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Unavailability.changeset()
    |> Repo.insert()
    |> result(&normalize_window/1)
  end

  @impl true
  def delete_unavailability(%{organization_id: organization_id}, space_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Unavailability{} = window <-
           Unavailability
           |> where([u], u.organization_id == ^organization_id)
           |> where([u], u.space_id == ^space_id and u.id == ^id)
           |> Repo.one() do
      window |> Repo.delete() |> result(&normalize_window/1)
    else
      _missing -> {:error, :not_found}
    end
  end

  defp cast_ids(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> [id]
      :error -> []
    end
  end

  defp normalize_space(space), do: Map.take(space, @space_fields)

  defp normalize_plan(plan),
    do: Map.take(plan, [:id, :location_id, :name, :media_id, :sort_order])

  defp normalize_window(window),
    do: Map.take(window, [:id, :space_id, :starts_at, :ends_at, :reason, :created_by_id])

  defp result({:ok, value}, normalize), do: {:ok, normalize.(value)}
  defp result(error, _normalize), do: error
end
