defmodule MilosTraining.Widgets.Domain.WidgetSnapshotTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Widgets.Domain.WidgetSnapshot

  @now ~U[2026-11-23 17:00:00Z]
  @water %{ml: 500, goal_ml: 2000, glass_ml: 250, count: 2, status: "partial"}

  defp item(kind, minutes, attrs \\ %{}) do
    Map.merge(
      %{
        kind: kind,
        title: kind,
        at: minutes && DateTime.add(@now, minutes * 60),
        status: "approved",
        source: %{name: "Box"}
      },
      attrs
    )
  end

  test "water, the first three items and the next booked class" do
    items = [
      item("wod", nil, %{status: nil}),
      item("class", -30),
      item("class", -10),
      item("class", 60)
    ]

    snapshot = WidgetSnapshot.build(%{items: items, water: @water, consented: true}, @now)

    assert snapshot.water == Map.put(@water, :can_add, true)
    assert length(snapshot.today) == 3
    assert %{kind: "wod", box_name: "Box"} = hd(snapshot.today)
    # 30′ ago is past its window; 10′ ago is still the class to check in to.
    assert snapshot.next_class.at == DateTime.add(@now, -600)
    assert snapshot.generated_at == @now
  end

  test "hidden water is null, no consent cannot add, pending bookings are no class" do
    snapshot =
      WidgetSnapshot.build(
        %{items: [item("class", 30, %{status: "pending"})], water: nil, consented: false},
        @now
      )

    assert snapshot.water == nil
    assert snapshot.next_class == nil

    assert %{can_add: false} =
             WidgetSnapshot.build(%{items: [], water: @water, consented: false}, @now).water
  end
end
