defmodule MilosTraining.Facility.Domain.GeofencePlanTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Facility.Domain.{CheckInRules, DoorCode, GeofencePlan, ResolveScan}

  @now ~U[2026-11-23 17:00:00Z]
  @rules CheckInRules.defaults()

  defp location(id, attrs \\ %{}),
    do: Map.merge(%{id: id, name: id, latitude: 37.9, longitude: 23.7, archived_at: nil}, attrs)

  defp booking(id, minutes, attrs \\ %{}) do
    Map.merge(
      %{
        id: id,
        name: "WOD",
        starts_at: DateTime.add(@now, minutes * 60),
        location_id: "a",
        attendance: nil
      },
      attrs
    )
  end

  test "a region per located place with an open or coming window" do
    [region] = GeofencePlan.regions([location("a")], [booking("b1", 60)], @rules, @now)

    assert region.location_id == "a"
    assert region.radius_m == 150
    assert [%{booking_id: "b1", opens_at: opens_at, closes_at: closes_at}] = region.windows
    assert opens_at == DateTime.add(@now, 30 * 60)
    assert closes_at == DateTime.add(@now, 75 * 60)
  end

  test "skips closed windows, attended bookings, unplaced and archived locations" do
    bookings = [
      booking("past", -20),
      booking("done", 10, %{attendance: "attended"}),
      booking("there", 10, %{location_id: "b"})
    ]

    assert GeofencePlan.regions([location("a")], bookings, @rules, @now) == []

    assert GeofencePlan.regions(
             [location("b", %{latitude: nil}), location("c", %{archived_at: @now})],
             [booking("x", 10, %{location_id: nil})],
             @rules,
             @now
           ) == []
  end

  test "a class without a location reminds at every place of the box" do
    regions =
      GeofencePlan.regions(
        [location("a"), location("b")],
        [booking("x", 10, %{location_id: nil})],
        @rules,
        @now
      )

    assert Enum.map(regions, & &1.location_id) == ["a", "b"]
  end

  test "soonest keeps the regions whose first window opens first" do
    early = %{location_id: "e", windows: [%{opens_at: @now}]}
    late = %{location_id: "l", windows: [%{opens_at: DateTime.add(@now, 60)}]}
    assert GeofencePlan.soonest([late, early], 1) == [early]
  end

  test "NFC and geofence are static sources like the poster" do
    facts = %{location_id: "a", member?: true, bookings: [], open_gym: %{covered?: true}}

    for source <- [:poster, :nfc, :geofence] do
      assert ResolveScan.decide(Map.put(facts, :source, source), @rules, @now) ==
               {:poster_no_booking, :member}
    end

    assert ResolveScan.decide(Map.put(facts, :source, :door), @rules, @now) == :open_gym
  end

  test "the NFC code differs from the poster code and verifies in constant time" do
    key = :crypto.strong_rand_bytes(32)
    code = DoorCode.nfc_code(key, "LOC")

    assert code == DoorCode.nfc_code(key, "loc")
    refute code == DoorCode.poster_code(key, "loc")
    assert DoorCode.verify_nfc(key, "loc", code) == :ok
    assert DoorCode.verify_nfc(key, "loc", "nope") == {:error, :invalid_door_code}
    assert DoorCode.verify_nfc(key, "loc", nil) == {:error, :invalid_door_code}
  end
end
