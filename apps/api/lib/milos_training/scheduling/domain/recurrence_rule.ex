defmodule MilosTraining.Scheduling.Domain.RecurrenceRule do
  @moduledoc """
  Pure weekly recurrence expansion for class series.

  Weekdays use ISO numbering (`1` is Monday and `7` is Sunday). Dates and the
  start time are interpreted in the series timezone before being converted to
  UTC.
  """

  @max_occurrences 600

  def occurrences(rule, opts \\ []) do
    starts_on = value(rule, :starts_on)
    ends_on = value(rule, :ends_on)
    weekdays = value(rule, :weekdays) || []
    excluded_dates = MapSet.new(value(rule, :excluded_dates) || [])
    horizon = Keyword.fetch!(opts, :horizon)

    with :ok <- validate_rule(starts_on, ends_on, weekdays, horizon) do
      if Date.before?(horizon, starts_on) do
        {:ok, []}
      else
        expand(
          starts_on,
          min_date(ends_on, horizon),
          weekdays,
          excluded_dates,
          value(rule, :local_start_time),
          value(rule, :timezone)
        )
      end
    end
  end

  defp validate_rule(_starts_on, _ends_on, [], _horizon), do: {:error, :weekdays_required}

  defp validate_rule(starts_on, ends_on, weekdays, horizon) do
    cond do
      not match?(%Date{}, starts_on) or not match?(%Date{}, horizon) ->
        {:error, :invalid_recurrence_range}

      not Enum.all?(weekdays, &(&1 in 1..7)) ->
        {:error, :invalid_weekday}

      match?(%Date{}, ends_on) and Date.before?(ends_on, starts_on) ->
        {:error, :invalid_recurrence_range}

      true ->
        :ok
    end
  end

  defp expand(starts_on, ends_on, weekdays, excluded_dates, local_start_time, timezone) do
    starts_on
    |> Date.range(ends_on)
    |> Enum.reduce_while({:ok, []}, fn date, {:ok, acc} ->
      if Date.day_of_week(date) in weekdays and not MapSet.member?(excluded_dates, date) do
        case local_datetime(date, local_start_time, timezone) do
          {:ok, datetime} when length(acc) < @max_occurrences ->
            {:cont, {:ok, [DateTime.shift_zone!(datetime, "Etc/UTC") | acc]}}

          {:ok, _datetime} ->
            {:halt, {:error, :too_many_occurrences}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, occurrences} -> {:ok, Enum.reverse(occurrences)}
      error -> error
    end
  end

  defp local_datetime(date, %Time{} = time, timezone) when is_binary(timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, _before, _after} -> {:error, :invalid_local_start_time}
      {:error, _reason} -> {:error, :invalid_timezone}
    end
  end

  defp local_datetime(_date, _time, _timezone), do: {:error, :invalid_local_start_time}

  defp min_date(nil, horizon), do: horizon

  defp min_date(%Date{} = ends_on, horizon) do
    if Date.before?(ends_on, horizon), do: ends_on, else: horizon
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
