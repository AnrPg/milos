defmodule MilosTraining.Facility do
  @moduledoc """
  Facility context (ADR-097): gym locations and open-gym check-ins. Check-ins
  that consume package visits go through `Application.CheckInOpenGym`.
  """

  alias MilosTraining.Facility.Domain.{GeoDistance, PlacePolicy}
  alias MilosTraining.Facility.FacilityStore

  @doc "Kilometres between two `{latitude, longitude}` points; nil when either is missing."
  def distance_km(from, to), do: GeoDistance.km(from, to)

  @doc "Accessibility features a location can declare (ADR-141)."
  def accessibility_features, do: PlacePolicy.accessibility_features()

  @doc """
  Address suggestions for pinning a location (ADR-141). `near` biases them
  towards a `{latitude, longitude}`; `language` is a locale code.
  """
  def search_addresses(query, opts \\ []) when is_binary(query) do
    case String.trim(query) do
      query when byte_size(query) < 3 -> {:ok, []}
      query -> geocoder().search(String.slice(query, 0, 200), Keyword.put_new(opts, :limit, 5))
    end
  end

  @doc "The address and neighbourhood at a dropped pin, or nil when there is none."
  def reverse_geocode(latitude, longitude, opts \\ []),
    do: geocoder().reverse(latitude, longitude, opts)

  defp geocoder, do: Application.fetch_env!(:milos_training, :geocoder)

  def list_locations(context, opts \\ []), do: FacilityStore.list_locations(context, opts)
  def get_location(context, id), do: FacilityStore.get_location(context, id)
  def create_location(context, params), do: FacilityStore.create_location(context, params)

  def update_location(context, id, params),
    do: FacilityStore.update_location(context, id, params)

  def archive_location(context, id), do: FacilityStore.archive_location(context, id)
  def get_check_in(context, user_id, date), do: FacilityStore.get_check_in(context, user_id, date)
  def create_check_in(context, attrs), do: FacilityStore.create_check_in(context, attrs)
  def list_check_ins(context, filters \\ %{}), do: FacilityStore.list_check_ins(context, filters)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: MilosTraining.Facility.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
