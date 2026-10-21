defmodule Palee.Facility.Domain.CheckInRulesTest do
  use ExUnit.Case, async: true

  alias Palee.Facility.Domain.CheckInRules

  test "defaults" do
    assert CheckInRules.effective(nil) == %{
             window_before_minutes: 30,
             window_after_minutes: 15,
             open_gym_requires_package: true,
             visitor_trial_offer: true,
             desk_override: false,
             door_rotation_seconds: 30,
             member_code_mode: "rotating",
             geofence_reminder: true
           }

    assert CheckInRules.effective(%{window_before_minutes: 10, desk_override: nil}).window_before_minutes ==
             10

    assert CheckInRules.effective(%{desk_override: nil}).desk_override == false
  end

  test "validate accepts string or atom keys and ignores unknown ones" do
    assert {:ok, %{window_before_minutes: 45, desk_override: true}} =
             CheckInRules.validate(%{
               "window_before_minutes" => 45,
               "x" => 1,
               desk_override: true
             })

    assert {:ok, %{}} = CheckInRules.validate(%{})
  end

  test "validate rejects bad values with field messages" do
    assert {:error, errors} =
             CheckInRules.validate(%{
               window_before_minutes: -1,
               window_after_minutes: 121,
               door_rotation_seconds: 20,
               desk_override: "yes"
             })

    assert Keyword.keys(errors) |> Enum.sort() ==
             [
               :desk_override,
               :door_rotation_seconds,
               :window_after_minutes,
               :window_before_minutes
             ]

    assert {:error, [window_before_minutes: _]} =
             CheckInRules.validate(%{window_before_minutes: 1.5})

    assert {:ok, _} =
             CheckInRules.validate(%{window_before_minutes: 0, window_after_minutes: 120})

    assert {:error, _} = CheckInRules.validate("nope")
  end

  test "booking window edges are inclusive" do
    starts = ~U[2026-10-20 18:00:00Z]

    assert CheckInRules.in_window?(nil, starts, ~U[2026-10-20 17:30:00Z])
    refute CheckInRules.in_window?(nil, starts, ~U[2026-10-20 17:29:59Z])
    assert CheckInRules.in_window?(nil, starts, ~U[2026-10-20 18:15:00Z])
    refute CheckInRules.in_window?(nil, starts, ~U[2026-10-20 18:15:01Z])

    settings = %{window_before_minutes: 5, window_after_minutes: 0}
    refute CheckInRules.in_window?(settings, starts, ~U[2026-10-20 17:54:00Z])
    assert CheckInRules.in_window?(settings, starts, ~U[2026-10-20 18:00:00Z])
    refute CheckInRules.in_window?(settings, starts, ~U[2026-10-20 18:00:01Z])
  end
end
