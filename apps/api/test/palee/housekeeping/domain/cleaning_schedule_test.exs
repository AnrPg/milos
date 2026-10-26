defmodule Palee.Housekeeping.Domain.CleaningScheduleTest do
  use ExUnit.Case, async: true

  alias Palee.Housekeeping.Domain.CleaningSchedule

  test "weekdays and times are validated, ordered and deduplicated" do
    assert {:ok, %{weekdays: [1, 3, 5], times: [~T[07:00:00], ~T[21:30:00]], comment: "Mop"}} =
             CleaningSchedule.normalize(%{
               "weekdays" => [5, 1, 3, 1],
               "times" => ["21:30", "07:00:00", "07:00"],
               "comment" => "  Mop "
             })

    assert {:ok, %{times: [], comment: nil}} =
             CleaningSchedule.normalize(%{weekdays: [7], comment: "  "})

    for attrs <- [
          %{weekdays: []},
          %{weekdays: [0]},
          %{weekdays: [8]},
          %{weekdays: [1], times: ["25:00"]},
          %{weekdays: [1], times: List.duplicate("07:00", 13)},
          %{weekdays: [1], comment: String.duplicate("x", 501)},
          %{}
        ] do
      assert CleaningSchedule.normalize(attrs) == {:error, :invalid_cleaning_schedule},
             inspect(attrs)
    end
  end

  test "what is due on a day, and how much of it is done" do
    # 2026-12-07 is a Monday.
    monday = ~D[2026-12-07]

    spaces = [%{id: "showers"}, %{id: "cardio"}, %{id: "rehab"}, %{id: "office"}]

    schedules = [
      %{space_id: "showers", weekdays: [1, 3], times: [~T[07:00:00], ~T[20:00:00]], comment: "x"},
      %{space_id: "cardio", weekdays: [1], times: [], comment: nil},
      %{space_id: "rehab", weekdays: [2], times: [~T[09:00:00]], comment: nil}
    ]

    assert [
             %{space_id: "showers", cleanings_due: 2, cleanings_done: 1, done: false},
             %{space_id: "cardio", cleanings_due: 1, cleanings_done: 3, done: true}
           ] =
             CleaningSchedule.due(spaces, schedules, %{"showers" => 1, "cardio" => 3}, monday)

    assert [%{space_id: "rehab", done: false}] =
             CleaningSchedule.due(spaces, schedules, %{}, Date.add(monday, 1))
  end
end
