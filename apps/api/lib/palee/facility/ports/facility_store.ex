defmodule Palee.Facility.Ports.FacilityStore do
  @moduledoc "Persistence port of the Facility context (ADR-097)."

  @type context :: %{organization_id: binary()}

  @callback list_locations(context(), keyword()) :: [map()]
  @callback get_location(context(), binary()) :: map() | nil
  @callback create_location(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_location(context(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback archive_location(context(), binary()) :: {:ok, map()} | {:error, term()}
  @callback get_check_in(context(), binary(), Date.t()) :: map() | nil
  @callback create_check_in(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_check_ins(context(), map()) :: [map()]

  # ADR-155: door codes, scans and the owner's check-in rules.
  @callback get_check_in_by_id(context(), binary()) :: map() | nil
  @callback delete_check_in(context(), binary()) :: {:ok, map()} | {:error, term()}
  @callback get_door_secret(context(), binary()) :: binary() | nil
  @callback rotate_door_secret(context(), binary(), binary(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback get_check_in_settings(context()) :: map() | nil
  @callback put_check_in_settings(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback record_visitor_scan(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_visitor_scans(context(), map()) :: [map()]
  # Board 10: the printed poster and static member codes.
  @callback get_poster(context(), binary()) :: map() | nil
  @callback rotate_poster_secret(context(), binary(), binary(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback set_poster_enabled(context(), binary(), boolean()) :: {:ok, map()} | {:error, term()}
  # ADR-173: the NFC door tag, the poster's twin.
  @callback get_nfc_tag(context(), binary()) :: map() | nil
  @callback rotate_nfc_secret(context(), binary(), binary(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback set_nfc_enabled(context(), binary(), boolean()) :: {:ok, map()} | {:error, term()}
  @callback get_active_member_code(context(), binary()) :: map() | nil
  @callback get_member_code(context(), binary()) :: map() | nil
  @callback get_member_code_by_serial(context(), binary()) :: map() | nil
  @callback create_member_code(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback revoke_member_codes(context(), map(), String.t(), DateTime.t()) :: [map()]
  @doc "The box behind a door, before any tenant is known (a narrow definer lookup)."
  @callback door_location(binary()) :: map() | nil
end
