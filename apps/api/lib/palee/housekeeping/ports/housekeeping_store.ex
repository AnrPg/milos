defmodule Palee.Housekeeping.Ports.HousekeepingStore do
  @moduledoc """
  Persistence port for the cleaning log (ADR-102) and the cleaning schedule
  (ADR-202). The cleaned areas are spaces, owned by `Palee.Spaces`.
  """

  @callback last_cleaned(map(), [binary()]) :: %{binary() => DateTime.t()}
  @callback start_entry(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_entry(map(), binary()) :: map() | nil
  @callback finish_entry(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_entries(map(), map()) :: [map()]
  @callback list_schedules(map()) :: [map()]
  @callback put_schedule(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_schedule(map(), binary()) :: :ok | {:error, term()}
end
