defmodule Palee.Scheduling.Domain.SeriesEditTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.SeriesEdit

  @athens "Europe/Athens"

  defp occurrence(id, iso), do: %{id: id, scheduled_at: DateTime.from_iso8601(iso) |> elem(1)}

  describe "scope/1" do
    test "defaults to this class and reads all and ranges" do
      assert SeriesEdit.scope(%{}) == {:ok, :this}
      assert SeriesEdit.scope(%{"series_scope" => "all"}) == {:ok, :all}

      assert SeriesEdit.scope(%{
               series_scope: "range",
               range_from: "2026-11-02",
               range_to: "2026-11-09"
             }) ==
               {:ok, {:range, ~D[2026-11-02], ~D[2026-11-09]}}
    end

    test "refuses unknown scopes and ranges without both dates in order" do
      assert SeriesEdit.scope(%{"series_scope" => "some"}) == {:error, :invalid_series_scope}

      assert SeriesEdit.scope(%{"series_scope" => "range", "range_from" => "2026-11-02"}) ==
               {:error, :series_range_required}

      assert SeriesEdit.scope(%{
               "series_scope" => "range",
               "range_from" => "2026-11-09",
               "range_to" => "2026-11-02"
             }) ==
               {:error, :series_range_required}
    end
  end

  test "targets are upcoming classes in the range by the gym's date, without the edited one" do
    now = ~U[2026-11-01 12:00:00Z]

    occurrences = [
      occurrence("past", "2026-11-01T05:00:00Z"),
      occurrence("edited", "2026-11-02T05:00:00Z"),
      # 23:30 UTC on the 2nd is already the 3rd in Athens.
      occurrence("late", "2026-11-02T23:30:00Z"),
      occurrence("out", "2026-11-05T05:00:00Z")
    ]

    ids = fn scope ->
      occurrences |> SeriesEdit.targets(scope, @athens, "edited", now) |> Enum.map(& &1.id)
    end

    assert ids.(:this) == []
    assert ids.(:all) == ["late", "out"]
    assert ids.({:range, ~D[2026-11-03], ~D[2026-11-04]}) == ["late"]
  end

  test "a new time of day lands on each class's own date across a DST change" do
    original = ~U[2030-10-25 04:00:00Z]
    # 07:00 → 08:30 Athens time (UTC+3 in October).
    time = SeriesEdit.new_local_time(original, "2030-10-25T05:30:00Z", @athens)
    assert time == ~T[08:30:00]

    # After the 27 October 2030 change Athens is UTC+2.
    after_dst = occurrence("next", "2030-11-01T05:00:00Z")

    assert SeriesEdit.changes_for(
             after_dst,
             %{"capacity" => 8},
             time,
             @athens,
             ~U[2030-10-20 00:00:00Z]
           ) == %{
             "capacity" => 8,
             "scheduled_at" => ~U[2030-11-01 06:30:00Z]
           }
  end

  test "a new time already past keeps the class's own time" do
    # At 04:30, a class at 05:00 cannot move to 04:00 today.
    past = occurrence("today", "2020-01-01T05:00:00Z")

    assert SeriesEdit.changes_for(
             past,
             %{"capacity" => 8},
             ~T[04:00:00],
             "Etc/UTC",
             ~U[2020-01-01 04:30:00Z]
           ) == %{
             "capacity" => 8
           }
  end

  test "moving only the date keeps the others' time and the series's" do
    assert SeriesEdit.new_local_time(~U[2026-10-23 04:00:00Z], "2026-10-27T05:00:00Z", @athens) ==
             nil

    assert SeriesEdit.template_changes(%{"name" => "WOD"}, nil) == %{"name" => "WOD"}
  end

  test "only the shared fields are passed on" do
    params = %{name: "WOD", master_workout_id: "w", scheduled_at: "x", capacity: 9}
    assert SeriesEdit.shared_changes(params) == %{"name" => "WOD", "capacity" => 9}
  end
end
