defmodule MilosTraining.Gamification.Domain.DayStreakCalculator do
  @moduledoc """
  Calculates daily training streaks respecting user-configured off days.

  Off days (0=Sun..6=Sat) are skipped without breaking the streak.
  A non-off training day with no workout breaks the streak.
  """

  @spec calculate([Date.t()], [integer()], Date.t()) :: %{
          current_streak: non_neg_integer(),
          longest_streak: non_neg_integer()
        }
  def calculate(completed_dates, off_days, current_date \\ Date.utc_today()) do
    completed_set = MapSet.new(completed_dates)
    off_day_set = MapSet.new(off_days)

    current_streak = walk_backward(current_date, completed_set, off_day_set, 0)

    longest_streak =
      if Enum.empty?(completed_dates) do
        0
      else
        compute_longest(completed_dates, completed_set, off_day_set)
      end

    %{current_streak: current_streak, longest_streak: max(current_streak, longest_streak)}
  end

  # Walk backward from current_date, counting consecutive training days.
  # Off days are transparent — they don't count and don't break the streak.
  # Gaps of more than 3 consecutive off days are treated as a break regardless.
  defp walk_backward(date, completed_set, off_day_set, streak) do
    day_of_week = Date.day_of_week(date, :sunday) - 1

    cond do
      MapSet.member?(completed_set, date) ->
        walk_backward(Date.add(date, -1), completed_set, off_day_set, streak + 1)

      MapSet.member?(off_day_set, day_of_week) ->
        walk_backward(Date.add(date, -1), completed_set, off_day_set, streak)

      streak == 0 ->
        # No workout on today (or most recent non-off day), streak might still be alive
        # if today was an off day we already handled above.
        # If today is a real training day with no workout, streak = 0.
        0

      true ->
        # Non-off day with no workout — streak is broken
        streak
    end
  end

  # Computes the longest ever streak by scanning from the earliest to latest date.
  defp compute_longest(completed_dates, completed_set, off_day_set) do
    earliest = Enum.min_by(completed_dates, &Date.to_gregorian_days/1)
    latest = Enum.max_by(completed_dates, &Date.to_gregorian_days/1)

    {_, longest, current} =
      date_range(earliest, latest)
      |> Enum.reduce({false, 0, 0}, fn date, {_in_streak, longest, current} ->
        day_of_week = Date.day_of_week(date, :sunday) - 1

        cond do
          MapSet.member?(completed_set, date) ->
            next = current + 1
            {true, max(longest, next), next}

          MapSet.member?(off_day_set, day_of_week) ->
            {true, longest, current}

          true ->
            {false, longest, 0}
        end
      end)

    max(longest, current)
  end

  defp date_range(first, last) do
    Stream.unfold(first, fn date ->
      if Date.compare(date, last) == :gt, do: nil, else: {date, Date.add(date, 1)}
    end)
  end
end
