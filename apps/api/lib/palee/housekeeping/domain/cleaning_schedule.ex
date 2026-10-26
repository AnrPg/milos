defmodule Palee.Housekeeping.Domain.CleaningSchedule do
  @moduledoc """
  The cleaning schedule (ADR-202): per space, the weekdays (ISO, 1 = Monday)
  and the times of day it should be cleaned, with a comment for the cleaning
  staff ("mop the mats with disinfectant").

  A space is due on a day when the day is one of its weekdays. Each time is
  one cleaning; a space with no times is cleaned once that day. A space is
  done for the day once it has as many finished cleanings that day as it
  has times.
  """

  @max_times 12
  @max_comment 500

  @doc "Validates and orders a schedule's weekdays, times and comment."
  def normalize(attrs) when is_map(attrs) do
    with {:ok, weekdays} <- weekdays(value(attrs, :weekdays)),
         {:ok, times} <- times(value(attrs, :times) || []),
         {:ok, comment} <- comment(value(attrs, :comment)) do
      {:ok, %{weekdays: weekdays, times: times, comment: comment}}
    end
  end

  defp weekdays(list) when is_list(list) and list != [] do
    if Enum.all?(list, &(is_integer(&1) and &1 in 1..7)),
      do: {:ok, list |> Enum.uniq() |> Enum.sort()},
      else: {:error, :invalid_cleaning_schedule}
  end

  defp weekdays(_list), do: {:error, :invalid_cleaning_schedule}

  defp times(list) when is_list(list) and length(list) <= @max_times do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case time(item) do
        {:ok, time} -> {:cont, {:ok, [time | acc]}}
        :error -> {:halt, {:error, :invalid_cleaning_schedule}}
      end
    end)
    |> case do
      {:ok, times} -> {:ok, times |> Enum.uniq() |> Enum.sort(Time)}
      error -> error
    end
  end

  defp times(_list), do: {:error, :invalid_cleaning_schedule}

  defp time(%Time{} = time), do: {:ok, %{time | second: 0, microsecond: {0, 0}}}

  defp time(value) when is_binary(value) do
    padded = if String.length(value) == 5, do: value <> ":00", else: value

    case Time.from_iso8601(padded) do
      {:ok, time} -> time(time)
      _invalid -> :error
    end
  end

  defp time(_value), do: :error

  defp comment(nil), do: {:ok, nil}

  defp comment(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:ok, nil}
      trimmed -> if String.length(trimmed) <= @max_comment, do: {:ok, trimmed}, else: too_long()
    end
  end

  defp comment(_text), do: {:error, :invalid_cleaning_schedule}

  defp too_long, do: {:error, :invalid_cleaning_schedule}

  @doc "Whether a schedule is due on `date`."
  def due_on?(%{weekdays: weekdays}, %Date{} = date), do: Date.day_of_week(date) in weekdays

  @doc "How many cleanings a schedule asks for on a day it is due."
  def cleanings_due(%{times: []}), do: 1
  def cleanings_due(%{times: times}), do: length(times)

  @doc """
  What is due on `date`: one row per space whose schedule is due, in the
  order of `spaces`. `finished_today` counts the finished cleanings of each
  space on that day (`%{space_id => count}`).
  """
  def due(spaces, schedules, finished_today, %Date{} = date) do
    by_space = Map.new(schedules, &{&1.space_id, &1})

    spaces
    |> Enum.filter(&(Map.has_key?(by_space, &1.id) and due_on?(by_space[&1.id], date)))
    |> Enum.map(fn space ->
      schedule = by_space[space.id]
      done = Map.get(finished_today, space.id, 0)
      due = cleanings_due(schedule)

      %{
        space_id: space.id,
        times: schedule.times,
        comment: schedule.comment,
        cleanings_due: due,
        cleanings_done: done,
        done: done >= due
      }
    end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
