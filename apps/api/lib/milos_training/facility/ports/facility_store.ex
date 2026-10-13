defmodule MilosTraining.Facility.Ports.FacilityStore do
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
end
