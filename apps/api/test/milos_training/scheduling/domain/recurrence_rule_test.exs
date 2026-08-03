defmodule MilosTraining.Scheduling.Domain.RecurrenceRuleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Scheduling.Domain.RecurrenceRule

  test "expands selected weekdays and omits excluded local dates" do
    rule = %{
      starts_on: ~D[2026-08-03],
      ends_on: ~D[2026-08-13],
      local_start_time: ~T[17:00:00],
      timezone: "Etc/UTC",
      weekdays: [1, 4],
      excluded_dates: [~D[2026-08-06]]
    }

    assert {:ok,
            [
              ~U[2026-08-03 17:00:00Z],
              ~U[2026-08-10 17:00:00Z],
              ~U[2026-08-13 17:00:00Z]
            ]} = RecurrenceRule.occurrences(rule, horizon: ~D[2027-08-03])
  end

  test "uses the supplied horizon for an open-ended series" do
    rule = %{
      starts_on: ~D[2026-08-03],
      ends_on: nil,
      local_start_time: ~T[09:30:00],
      timezone: "Etc/UTC",
      weekdays: [1],
      excluded_dates: []
    }

    assert {:ok, [~U[2026-08-03 09:30:00Z], ~U[2026-08-10 09:30:00Z]]} =
             RecurrenceRule.occurrences(rule, horizon: ~D[2026-08-10])
  end

  test "converts the local class time to UTC" do
    rule = %{
      starts_on: ~D[2026-08-03],
      ends_on: ~D[2026-08-03],
      local_start_time: ~T[17:00:00],
      timezone: "Europe/Athens",
      weekdays: [1],
      excluded_dates: []
    }

    assert {:ok, [~U[2026-08-03 14:00:00Z]]} =
             RecurrenceRule.occurrences(rule, horizon: ~D[2026-08-03])
  end

  test "rejects empty weekdays and an end before the start" do
    base = %{
      starts_on: ~D[2026-08-03],
      local_start_time: ~T[17:00:00],
      timezone: "Etc/UTC",
      excluded_dates: []
    }

    assert {:error, :weekdays_required} =
             RecurrenceRule.occurrences(Map.merge(base, %{weekdays: [], ends_on: nil}),
               horizon: ~D[2026-08-10]
             )

    assert {:error, :invalid_recurrence_range} =
             RecurrenceRule.occurrences(
               Map.merge(base, %{weekdays: [1], ends_on: ~D[2026-08-02]}),
               horizon: ~D[2026-08-10]
             )
  end
end
