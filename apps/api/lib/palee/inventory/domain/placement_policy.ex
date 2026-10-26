defmodule Palee.Inventory.Domain.PlacementPolicy do
  @moduledoc """
  Where a machine stands (ADR-202). A machine row may be one physical item
  (quantity 1) or several interchangeable ones ("Treadmill", quantity 6), so
  its placement is a list of `{space, quantity}`: 5 in the cardio room, 1 in
  rehab. The quantities placed never exceed the quantity owned; the rest is
  unassigned. A single item is the same list with one entry of 1.
  """

  @doc """
  Validates a new placement for a machine owning `owned` items: merges
  repeated spaces, drops zero quantities, and refuses more than owned.
  Returns `[%{space_id, quantity}]` ordered as given.
  """
  def normalize(placements, owned) when is_list(placements) and is_integer(owned) do
    with {:ok, rows} <- rows(placements) do
      merged =
        rows
        |> Enum.reduce({[], %{}}, fn %{space_id: id, quantity: q}, {order, sums} ->
          order = if Map.has_key?(sums, id), do: order, else: [id | order]
          {order, Map.update(sums, id, q, &(&1 + q))}
        end)
        |> then(fn {order, sums} ->
          order |> Enum.reverse() |> Enum.map(&%{space_id: &1, quantity: sums[&1]})
        end)
        |> Enum.reject(&(&1.quantity == 0))

      if placed(merged) <= owned,
        do: {:ok, merged},
        else: {:error, :placement_exceeds_quantity}
    end
  end

  def normalize(_placements, _owned), do: {:error, :invalid_placement}

  defp rows(placements) do
    Enum.reduce_while(placements, {:ok, []}, fn row, {:ok, acc} ->
      id = Map.get(row, :space_id) || Map.get(row, "space_id")
      quantity = Map.get(row, :quantity) || Map.get(row, "quantity")

      if is_binary(id) and is_integer(quantity) and quantity >= 0,
        do: {:cont, {:ok, [%{space_id: id, quantity: quantity} | acc]}},
        else: {:halt, {:error, :invalid_placement}}
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  @doc "How many items a placement puts somewhere."
  def placed(placements), do: placements |> Enum.map(& &1.quantity) |> Enum.sum()

  @doc "How many items stand nowhere in particular."
  def unassigned(owned, placements), do: max(owned - placed(placements), 0)

  @doc "`:ok` when a machine can own `quantity` items with what is placed already."
  def check_quantity(nil, _placements), do: :ok

  def check_quantity(quantity, placements) when is_integer(quantity) do
    if quantity >= placed(placements),
      do: :ok,
      else: {:error, :placement_exceeds_quantity}
  end

  def check_quantity(_quantity, _placements), do: :ok
end
