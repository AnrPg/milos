defmodule Palee.Inventory.Domain.PlacementPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Inventory.Domain.PlacementPolicy

  test "several interchangeable items spread over spaces; the rest is unassigned" do
    assert {:ok, placed} =
             PlacementPolicy.normalize(
               [
                 %{"space_id" => "cardio", "quantity" => 3},
                 %{space_id: "rehab", quantity: 1},
                 %{space_id: "cardio", quantity: 2},
                 %{space_id: "office", quantity: 0}
               ],
               6
             )

    assert placed == [
             %{space_id: "cardio", quantity: 5, positions: []},
             %{space_id: "rehab", quantity: 1, positions: []}
           ]

    assert PlacementPolicy.unassigned(6, placed) == 0
    assert PlacementPolicy.unassigned(8, placed) == 2
  end

  test "a single item stands in one space" do
    assert {:ok, [%{space_id: "cardio", quantity: 1}]} =
             PlacementPolicy.normalize([%{space_id: "cardio", quantity: 1}], 1)

    assert {:ok, []} = PlacementPolicy.normalize([], 1)
  end

  test "more than owned, or malformed rows, are refused" do
    assert PlacementPolicy.normalize(
             [%{space_id: "a", quantity: 4}, %{space_id: "b", quantity: 3}],
             6
           ) ==
             {:error, :placement_exceeds_quantity}

    assert PlacementPolicy.normalize([%{space_id: "a", quantity: -1}], 6) ==
             {:error, :invalid_placement}

    assert PlacementPolicy.normalize([%{quantity: 1}], 6) == {:error, :invalid_placement}
    assert PlacementPolicy.normalize(:nope, 6) == {:error, :invalid_placement}
  end

  test "ADR-290: items pinned on the floor plan, at most one pin per item there" do
    assert {:ok, [%{space_id: "cardio", quantity: 2, positions: [[0.1235, 0.5], [0.3, 1.0]]}]} =
             PlacementPolicy.normalize(
               [
                 %{space_id: "cardio", quantity: 1, positions: [[0.123456, 0.5]]},
                 %{"space_id" => "cardio", "quantity" => 1, "positions" => [[0.3, 1]]}
               ],
               2
             )

    assert PlacementPolicy.normalize(
             [%{space_id: "a", quantity: 1, positions: [[0.1, 0.1], [0.2, 0.2]]}],
             3
           ) == {:error, :invalid_machine_position}

    assert PlacementPolicy.normalize([%{space_id: "a", quantity: 1, positions: [[1.5, 0]]}], 1) ==
             {:error, :invalid_machine_position}

    assert PlacementPolicy.normalize([%{space_id: "a", quantity: 1, positions: "x"}], 1) ==
             {:error, :invalid_machine_position}
  end

  test "a machine cannot own fewer than are placed" do
    placed = [%{space_id: "a", quantity: 4}]
    assert PlacementPolicy.check_quantity(4, placed) == :ok
    assert PlacementPolicy.check_quantity(3, placed) == {:error, :placement_exceeds_quantity}
    assert PlacementPolicy.check_quantity(nil, placed) == :ok
  end
end
