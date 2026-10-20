defmodule MilosTraining.Facility do
  @moduledoc """
  Facility context (ADR-097): gym locations and open-gym check-ins. Check-ins
  that consume package visits go through `Application.CheckInOpenGym`.
  """

  alias MilosTraining.Facility.Domain.{CheckInRules, GeoDistance, MapLink, PlacePolicy}
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

  @doc """
  The pin and address behind a pasted Google Maps link. Short links are
  expanded first; the address comes from reverse geocoding the point.
  """
  def resolve_map_link(url, opts \\ []) when is_binary(url) do
    url = String.trim(url)

    with true <- MapLink.link?(url) || {:error, :not_a_map_link},
         {:ok, long_url} <- expand_map_link(url),
         {:ok, {latitude, longitude}} <- MapLink.coordinates(long_url) do
      case reverse_geocode(latitude, longitude, opts) do
        {:ok, %{} = place} -> {:ok, place}
        _none_or_down -> {:ok, bare_place(latitude, longitude)}
      end
    else
      {:error, :no_coordinates} -> {:error, :map_link_unresolved}
      error -> error
    end
  end

  defp expand_map_link(url) do
    if MapLink.short_host?(URI.parse(url).host),
      do: Application.fetch_env!(:milos_training, :map_link_resolver).expand(url),
      else: {:ok, url}
  end

  defp bare_place(latitude, longitude) do
    %{
      label: "#{latitude}, #{longitude}",
      address: nil,
      neighbourhood: nil,
      city: nil,
      country_code: nil,
      latitude: latitude,
      longitude: longitude
    }
  end

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

  # ADR-155: QR check-in.
  def get_check_in_by_id(context, id), do: FacilityStore.get_check_in_by_id(context, id)
  def delete_check_in(context, id), do: FacilityStore.delete_check_in(context, id)

  @doc "A location's door seed (bytes), or nil. Only key derivation may see it."
  def get_door_secret(context, location_id),
    do: FacilityStore.get_door_secret(context, location_id)

  @doc "«Νέος κωδικός πόρτας»: a fresh seed; every code shown so far stops working."
  def rotate_door_secret(context, location_id, now),
    do: FacilityStore.rotate_door_secret(context, location_id, :crypto.strong_rand_bytes(32), now)

  @doc "The printed poster of a location: `%{enabled, secret, rotated_at}` or nil."
  def get_poster(context, location_id), do: FacilityStore.get_poster(context, location_id)

  @doc "«Νέος κωδικός αφίσας»: a fresh poster seed; every printed copy stops working."
  def rotate_poster_secret(context, location_id, now),
    do:
      FacilityStore.rotate_poster_secret(
        context,
        location_id,
        :crypto.strong_rand_bytes(32),
        now
      )

  def set_poster_enabled(context, location_id, enabled) when is_boolean(enabled),
    do: FacilityStore.set_poster_enabled(context, location_id, enabled)

  # Static member codes (board 10, Q5).
  def get_active_member_code(context, user_id),
    do: FacilityStore.get_active_member_code(context, user_id)

  def get_member_code(context, id), do: FacilityStore.get_member_code(context, id)

  def get_member_code_by_serial(context, serial),
    do: FacilityStore.get_member_code_by_serial(context, serial)

  @doc "A new code for a member; a concurrent issue wins and is returned instead."
  def issue_member_code(%{organization_id: organization_id} = context, user_id) do
    case FacilityStore.create_member_code(context, %{
           organization_id: organization_id,
           user_id: user_id,
           serial: Ecto.UUID.generate()
         }) do
      {:ok, code} ->
        {:ok, code}

      {:error, _changeset} = error ->
        case get_active_member_code(context, user_id) do
          nil -> error
          code -> {:ok, code}
        end
    end
  end

  @doc "Revokes active codes (`%{user_id: id}` or every code of the box); returns them."
  def revoke_member_codes(context, filters, reason, now),
    do: FacilityStore.revoke_member_codes(context, filters, reason, now)

  @doc "The box's check-in rules with defaults filled in."
  def check_in_rules(context),
    do: context |> FacilityStore.get_check_in_settings() |> CheckInRules.effective()

  @doc "Validates and saves a change to the box's check-in rules."
  def update_check_in_rules(context, attrs) do
    with {:ok, changes} <- CheckInRules.validate(attrs),
         {:ok, _saved} <-
           FacilityStore.put_check_in_settings(
             context,
             Map.merge(check_in_rules(context), changes)
           ) do
      {:ok, check_in_rules(context)}
    end
  end

  def record_visitor_scan(context, attrs), do: FacilityStore.record_visitor_scan(context, attrs)

  def list_visitor_scans(context, filters \\ %{}),
    do: FacilityStore.list_visitor_scans(context, filters)

  @doc "The box behind a door (name, branding, location name), or nil."
  def door_location(location_id), do: FacilityStore.door_location(location_id)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: MilosTraining.Facility.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
