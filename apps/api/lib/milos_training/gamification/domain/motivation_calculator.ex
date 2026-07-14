defmodule MilosTraining.Gamification.Domain.MotivationCalculator do
  @moduledoc """
  Calculates motivation score: % of last 10 weeks where completed workouts >= weekly_target.

  Off days are not considered — motivation is purely about hitting the weekly target.
  """

  @weeks_to_check 10

  @spec calculate([Date.t()], non_neg_integer(), Date.t()) :: float()
  def calculate(completed_dates, weekly_target, current_date \\ Date.utc_today())

  def calculate([], _target, _current_date), do: 0.0

  def calculate(completed_dates, weekly_target, current_date) do
    weeks_on_target =
      0..(@weeks_to_check - 1)
      |> Enum.count(fn weeks_ago ->
        week_start = Date.add(current_date, -7 * (weeks_ago + 1))
        week_end = Date.add(current_date, -7 * weeks_ago - 1)

        count =
          Enum.count(completed_dates, fn date ->
            Date.compare(date, week_start) != :lt and
              Date.compare(date, week_end) != :gt
          end)

        count >= weekly_target
      end)

    Float.round(weeks_on_target / @weeks_to_check * 100.0, 1)
  end
end
