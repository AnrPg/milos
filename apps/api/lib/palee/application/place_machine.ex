defmodule Palee.Application.PlaceMachine do
  @moduledoc """
  Where a machine stands (ADR-202): how many of it are in which space.
  Every space must be a usable space the caller works at, of the machine's
  own branch (a space without a branch fits any machine); the quantities
  placed never exceed the quantity owned (`placement_exceeds_quantity`).
  """

  alias Palee.Application.SpaceDirectory
  alias Palee.{Inventory, Organizations, Spaces}

  def call(context, machine_id, placements) when is_list(placements) do
    with %{} = machine <- Inventory.get_machine(context, machine_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, machine.location_id),
         {:ok, rows} <- Inventory.normalize_placement(placements, machine.quantity),
         :ok <- check_spaces(context, rows, machine.location_id),
         {:ok, placed} <- Inventory.place_machine(context, machine.id, rows) do
      {:ok,
       %{
         machine_id: machine.id,
         placements: Enum.map(placed, &Map.take(&1, [:space_id, :quantity])),
         unassigned: Inventory.unassigned(machine.quantity, placed)
       }}
    end
  end

  def call(_context, _machine_id, _placements), do: {:error, :invalid_placement}

  defp check_spaces(context, rows, location_id) do
    Enum.reduce_while(rows, :ok, fn %{space_id: id}, :ok ->
      with {:ok, space} <- SpaceDirectory.fetch(context, id),
           :ok <- Spaces.usable(space),
           :ok <- Spaces.same_branch(space, location_id) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end
end
