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
  ADR-290: each row may pin its items on the space's floor plan
  (`positions`, `[x, y]` within 0..1, at most one per item there).
  Returns `[%{space_id, quantity, positions}]` ordered as given.
  """
  def normalize(placements, owned) when is_list(placements) and is_integer(owned) do
    with {:ok, rows} <- rows(placements) do
      merged =
        rows
        |> Enum.reduce({[], %{}}, fn %{space_id: id, quantity: q, positions: p}, {order, sums} ->
          order = if Map.has_key?(sums, id), do: order, else: [id | order]
          {order, Map.update(sums, id, {q, p}, fn {sum, pins} -> {sum + q, pins ++ p} end)}
        end)
        |> then(fn {order, sums} ->
          order
          |> Enum.reverse()
          |> Enum.map(fn id ->
            {quantity, positions} = sums[id]
            %{space_id: id, quantity: quantity, positions: positions}
          end)
        end)
        |> Enum.reject(&(&1.quantity == 0))

      cond do
        placed(merged) > owned ->
          {:error, :placement_exceeds_quantity}

        Enum.any?(merged, &(length(&1.positions) > &1.quantity)) ->
          {:error, :invalid_machine_position}

        true ->
          {:ok, merged}
      end
    end
  end

  def normalize(_placements, _owned), do: {:error, :invalid_placement}

  defp rows(placements) do
    Enum.reduce_while(placements, {:ok, []}, fn row, {:ok, acc} ->
      id = Map.get(row, :space_id) || Map.get(row, "space_id")
      quantity = Map.get(row, :quantity) || Map.get(row, "quantity")

      with true <- (is_binary(id) and is_integer(quantity) and quantity >= 0) || :invalid,
           {:ok, positions} <- positions(Map.get(row, :positions) || Map.get(row, "positions")) do
        {:cont, {:ok, [%{space_id: id, quantity: quantity, positions: positions} | acc]}}
      else
        :invalid -> {:halt, {:error, :invalid_placement}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp positions(nil), do: {:ok, []}

  defp positions(list) when is_list(list) do
    if Enum.all?(list, &position?/1),
      do: {:ok, Enum.map(list, fn [x, y] -> [round4(x), round4(y)] end)},
      else: {:error, :invalid_machine_position}
  end

  defp positions(_other), do: {:error, :invalid_machine_position}

  defp position?([x, y]) when is_number(x) and is_number(y),
    do: x >= 0 and x <= 1 and y >= 0 and y <= 1

  defp position?(_other), do: false

  defp round4(value), do: Float.round(value / 1, 4)

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
