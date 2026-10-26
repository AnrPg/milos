defmodule Palee.Inventory.Ports.InventoryStore do
  @moduledoc "Persistence port for the gym's inventory (ADR-104)."

  @callback list_machines(map(), map()) :: [map()]
  @callback get_machine(map(), binary()) :: map() | nil
  @callback save_machine(map(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback add_machine_event(map(), binary(), map()) ::
              {:ok, %{machine: map(), event: map(), previous_status: atom()}} | {:error, term()}
  @callback list_machine_events(map(), map()) :: [map()]
  # ADR-202: how many of each machine stand in which space.
  @callback list_placements(map(), map()) :: [map()]
  @callback replace_placements(map(), binary(), [map()]) :: {:ok, [map()]} | {:error, term()}
  @callback list_supplies(map(), map()) :: [map()]
  @callback get_supply(map(), binary()) :: map() | nil
  @callback save_supply(map(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback record_movement(map(), binary(), map()) ::
              {:ok, %{supply: map(), movement: map()}} | {:error, term()}
  @callback list_movements(map(), map()) :: [map()]
  @callback add_supply_report(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_supply_reports(map(), map()) :: [map()]
end
