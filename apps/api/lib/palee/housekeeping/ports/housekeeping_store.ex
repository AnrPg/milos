defmodule Palee.Housekeeping.Ports.HousekeepingStore do
  @moduledoc "Persistence port for the cleaning log (ADR-102)."

  @callback list_areas(map(), map()) :: [map()]
  @callback get_area(map(), binary()) :: map() | nil
  @callback save_area(map(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback start_entry(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_entry(map(), binary()) :: map() | nil
  @callback finish_entry(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_entries(map(), map()) :: [map()]
end
