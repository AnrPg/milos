defmodule Palee.Facility.FacilityStore do
  @moduledoc false
  @behaviour Palee.Facility.Ports.FacilityStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :facility_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_locations(context, opts), do: tenant_call(context, :list_locations, [opts])

  @impl true
  def get_location(context, id), do: tenant_call(context, :get_location, [id])

  @impl true
  def create_location(context, params), do: tenant_call(context, :create_location, [params])

  @impl true
  def update_location(context, id, params),
    do: tenant_call(context, :update_location, [id, params])

  @impl true
  def archive_location(context, id), do: tenant_call(context, :archive_location, [id])

  @impl true
  def get_check_in(context, user_id, date),
    do: tenant_call(context, :get_check_in, [user_id, date])

  @impl true
  def create_check_in(context, attrs), do: tenant_call(context, :create_check_in, [attrs])

  @impl true
  def list_check_ins(context, filters), do: tenant_call(context, :list_check_ins, [filters])

  @impl true
  def get_check_in_by_id(context, id), do: tenant_call(context, :get_check_in_by_id, [id])

  @impl true
  def delete_check_in(context, id), do: tenant_call(context, :delete_check_in, [id])

  @impl true
  def get_door_secret(context, location_id),
    do: tenant_call(context, :get_door_secret, [location_id])

  @impl true
  def rotate_door_secret(context, location_id, secret, at),
    do: tenant_call(context, :rotate_door_secret, [location_id, secret, at])

  @impl true
  def get_check_in_settings(context), do: tenant_call(context, :get_check_in_settings, [])

  @impl true
  def put_check_in_settings(context, changes),
    do: tenant_call(context, :put_check_in_settings, [changes])

  @impl true
  def record_visitor_scan(context, attrs), do: tenant_call(context, :record_visitor_scan, [attrs])

  @impl true
  def list_visitor_scans(context, filters),
    do: tenant_call(context, :list_visitor_scans, [filters])

  @impl true
  def get_poster(context, location_id), do: tenant_call(context, :get_poster, [location_id])

  @impl true
  def rotate_poster_secret(context, location_id, secret, at),
    do: tenant_call(context, :rotate_poster_secret, [location_id, secret, at])

  @impl true
  def set_poster_enabled(context, location_id, enabled),
    do: tenant_call(context, :set_poster_enabled, [location_id, enabled])

  @impl true
  def get_nfc_tag(context, location_id), do: tenant_call(context, :get_nfc_tag, [location_id])

  @impl true
  def rotate_nfc_secret(context, location_id, secret, at),
    do: tenant_call(context, :rotate_nfc_secret, [location_id, secret, at])

  @impl true
  def set_nfc_enabled(context, location_id, enabled),
    do: tenant_call(context, :set_nfc_enabled, [location_id, enabled])

  @impl true
  def get_active_member_code(context, user_id),
    do: tenant_call(context, :get_active_member_code, [user_id])

  @impl true
  def get_member_code(context, id), do: tenant_call(context, :get_member_code, [id])

  @impl true
  def get_member_code_by_serial(context, serial),
    do: tenant_call(context, :get_member_code_by_serial, [serial])

  @impl true
  def create_member_code(context, attrs), do: tenant_call(context, :create_member_code, [attrs])

  @impl true
  def revoke_member_codes(context, filters, reason, at),
    do: tenant_call(context, :revoke_member_codes, [filters, reason, at])

  # No tenant yet: the definer function answers only for active boxes and
  # open locations, and returns what the door itself shows.
  @impl true
  def door_location(location_id), do: adapter().door_location(location_id)
end
