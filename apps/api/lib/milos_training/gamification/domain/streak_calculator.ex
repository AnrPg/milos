defmodule MilosTraining.Gamification.Domain.StreakCalculator do
  @default_target 2
  @default_shields 1

  def update(stats, opts) do
    completed_dates = Keyword.get(opts, :completed_dates, [])
    current_date = Keyword.fetch!(opts, :current_date)
    target = Keyword.get(opts, :target, @default_target)
    anchor_date = Keyword.get(opts, :anchor_date)
    shield_reset_day = Keyword.get(opts, :shield_reset_day)

    computed =
      calculate(completed_dates, anchor_date,
        current_date: current_date,
        target: target,
        shield_reset_day: shield_reset_day
      )

    %{
      current_streak: computed.current_streak,
      longest_streak: max(stats[:longest_streak] || 0, computed.longest_streak),
      current_streak_shields: computed.current_streak_shields,
      consistency_score: computed.consistency_score
    }
  end

  def calculate(completed_dates, opts) when is_list(opts) do
    calculate(completed_dates, nil, opts)
  end

  def calculate([], _anchor_date, _opts) do
    %{
      current_streak: 0,
      longest_streak: 0,
      current_streak_shields: @default_shields,
      consistency_score: 0.0
    }
  end

  def calculate(completed_dates, opts, []) when is_list(opts) do
    calculate(completed_dates, nil, opts)
  end

  def calculate(completed_dates, nil, opts) do
    calculate(completed_dates, earliest_date(completed_dates), opts)
  end

  def calculate(completed_dates, anchor_date, opts) do
    current_date = Keyword.fetch!(opts, :current_date)
    target = Keyword.get(opts, :target, @default_target)
    shield_reset_day = Keyword.get(opts, :shield_reset_day)
    normalized_anchor_date = anchor_date || earliest_date(completed_dates)
    current_week = week_start_for_date(current_date, normalized_anchor_date)

    weekly_map =
      completed_dates
      |> Enum.group_by(&week_start_for_date(&1, normalized_anchor_date))
      |> Map.new(fn {week_start, dates} -> {week_start, length(dates)} end)

    week_starts = week_range(normalized_anchor_date, current_week)

    {current_streak, longest_streak, shields_left, _last_reset_date} =
      Enum.reduce(
        week_starts,
        {0, 0, @default_shields, normalized_anchor_date},
        fn week_start, {current_streak, longest_streak, shields_left, last_reset_date} ->
          {shields_for_week, next_reset_date} =
            maybe_reset_shields(
              week_start,
              normalized_anchor_date,
              shields_left,
              last_reset_date,
              shield_reset_day
            )

          workouts = Map.get(weekly_map, week_start, 0)

          cond do
            workouts >= target ->
              next_streak = current_streak + 1
              {next_streak, max(longest_streak, next_streak), shields_for_week, next_reset_date}

            current_streak > 0 and shields_for_week > 0 ->
              {current_streak, longest_streak, shields_for_week - 1, next_reset_date}

            true ->
              {0, longest_streak, shields_for_week, next_reset_date}
          end
        end
      )

    %{
      current_streak: current_streak,
      longest_streak: longest_streak,
      current_streak_shields: shields_left,
      consistency_score: consistency_score(weekly_map, week_starts)
    }
  end

  defp maybe_reset_shields(
         week_start,
         anchor_date,
         shields_left,
         last_reset_date,
         shield_reset_day
       ) do
    week_end = Date.add(week_start, 6)
    next_reset_date = next_monthly_reset(anchor_date, last_reset_date, shield_reset_day)

    if Date.compare(next_reset_date, week_end) != :gt do
      maybe_reset_shields(
        week_start,
        anchor_date,
        @default_shields,
        next_reset_date,
        shield_reset_day
      )
    else
      {shields_left, last_reset_date}
    end
  end

  defp consistency_score(_weekly_map, []), do: 0.0

  defp consistency_score(weekly_map, week_starts) do
    lookback_weeks = Enum.take(week_starts, -12)
    active_weeks = Enum.count(lookback_weeks, &(Map.get(weekly_map, &1, 0) > 0))
    Float.round(active_weeks / max(length(lookback_weeks), 1) * 100.0, 2)
  end

  defp week_range(start_date, end_date) do
    Stream.unfold(start_date, fn current ->
      if Date.compare(current, end_date) == :gt do
        nil
      else
        {current, Date.add(current, 7)}
      end
    end)
    |> Enum.to_list()
  end

  defp week_start_for_date(date, anchor_date) do
    offset = Date.diff(date, anchor_date)
    bucket = div(max(offset, 0), 7)
    Date.add(anchor_date, bucket * 7)
  end

  defp earliest_date(dates), do: Enum.min_by(dates, &Date.to_gregorian_days/1)

  defp next_monthly_reset(anchor_date, current_reset_date, shield_reset_day) do
    current_reset_date
    |> month_shift(1)
    |> align_day(shield_reset_day || anchor_date.day)
  end

  defp month_shift(%Date{} = date, months) do
    year_month_index = date.year * 12 + (date.month - 1) + months
    year = div(year_month_index, 12)
    month = rem(year_month_index, 12) + 1
    day = min(date.day, Date.days_in_month(%Date{year: year, month: month, day: 1}))
    %Date{year: year, month: month, day: day}
  end

  defp align_day(%Date{} = date, day) do
    %{date | day: min(day, Date.days_in_month(date))}
  end
end
