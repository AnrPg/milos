defmodule MilosTraining.Infrastructure.Facility.EctoFacilityStore do
  @moduledoc "Ecto adapter of the Facility store (ADR-097)."

  @behaviour MilosTraining.Facility.Ports.FacilityStore

  import Ecto.Query

  alias MilosTraining.Facility.{CheckIn, Location}
  alias MilosTraining.Repo

  @impl true
  def list_locations(%{organization_id: organization_id}, opts) do
    Location
    |> where([location], location.organization_id == ^organization_id)
    |> maybe_active(Keyword.get(opts, :include_archived, false))
    |> order_by([location], asc: location.name)
    |> Repo.all()
    |> Enum.map(&normalize_location/1)
  end

  @impl true
  def get_location(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Location{} = location <-
           Repo.get_by(Location, id: id, organization_id: organization_id) do
      normalize_location(location)
    else
      _missing -> nil
    end
  end

  @impl true
  def create_location(%{organization_id: organization_id}, params) do
    params
    |> string_keys()
    |> Map.put("organization_id", organization_id)
    |> Location.create_changeset()
    |> Repo.insert()
    |> normalize_result(&normalize_location/1)
  end

  @impl true
  def update_location(%{organization_id: organization_id}, id, params) do
    case fetch_location(organization_id, id) do
      nil ->
        {:error, :not_found}

      location ->
        location
        |> Location.update_changeset(string_keys(params))
        |> Repo.update()
        |> normalize_result(&normalize_location/1)
    end
  end

  @impl true
  def archive_location(%{organization_id: organization_id}, id) do
    case fetch_location(organization_id, id) do
      nil ->
        {:error, :not_found}

      %Location{archived_at: nil} = location ->
        location
        |> Location.archive_changeset(DateTime.utc_now())
        |> Repo.update()
        |> normalize_result(&normalize_location/1)

      location ->
        {:ok, normalize_location(location)}
    end
  end

  @impl true
  def get_check_in(%{organization_id: organization_id}, user_id, %Date{} = date) do
    CheckIn
    |> where(
      [check_in],
      check_in.organization_id == ^organization_id and check_in.user_id == ^user_id and
        check_in.checked_in_on == ^date
    )
    |> check_in_query()
    |> Repo.one()
  end

  @impl true
  def create_check_in(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> CheckIn.changeset()
    |> Repo.insert()
    |> case do
      {:ok, check_in} ->
        {:ok,
         get_check_in(
           %{organization_id: organization_id},
           check_in.user_id,
           check_in.checked_in_on
         )}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @impl true
  def list_check_ins(%{organization_id: organization_id}, filters) do
    CheckIn
    |> where([check_in], check_in.organization_id == ^organization_id)
    |> maybe_filter(:checked_in_on, filters[:date])
    |> maybe_filter(:user_id, filters[:user_id])
    |> maybe_filter(:location_id, filters[:location_id])
    |> check_in_query()
    |> order_by([check_in], desc: check_in.checked_in_at)
    |> limit(^min(filters[:limit] || 200, 500))
    |> Repo.all()
  end

  defp check_in_query(query) do
    from check_in in query,
      left_join: user in "users",
      on: user.id == check_in.user_id,
      left_join: location in Location,
      on: location.id == check_in.location_id,
      select: %{
        id: check_in.id,
        organization_id: check_in.organization_id,
        user_id: check_in.user_id,
        nickname: user.nickname,
        location_id: check_in.location_id,
        location_name: location.name,
        checked_in_on: check_in.checked_in_on,
        checked_in_at: check_in.checked_in_at,
        source: check_in.source,
        recorded_by_id: check_in.recorded_by_id
      }
  end

  defp maybe_active(query, true), do: query
  defp maybe_active(query, _), do: where(query, [location], is_nil(location.archived_at))

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value),
    do: where(query, [check_in], field(check_in, ^field) == ^value)

  defp fetch_location(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Location, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  defp normalize_result({:ok, record}, normalize), do: {:ok, normalize.(record)}
  defp normalize_result({:error, changeset}, _normalize), do: {:error, changeset}

  defp normalize_location(%Location{} = location) do
    %{
      id: location.id,
      organization_id: location.organization_id,
      name: location.name,
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
      neighbourhood: location.neighbourhood,
      city: location.city,
      country_code: location.country_code,
      opening_hours: location.opening_hours,
      accessibility: location.accessibility,
      archived_at: location.archived_at,
      inserted_at: location.inserted_at,
      updated_at: location.updated_at
    }
  end

  defp string_keys(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
