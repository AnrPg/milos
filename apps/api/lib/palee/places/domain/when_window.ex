defmodule Palee.Places.Domain.WhenWindow do
  @moduledoc """
  «Πότε» of the Γύρω μου filter as UTC windows (ADR-154): the days of
  `today`, `tomorrow`, `weekend`, `week` or a date range, each cut to the
  parts of the day picked (`morning` 05:00–12:00, `midday` 12:00–17:00,
  `evening` 17:00–24:00), all on the wall clock of `time_zone` (the boxes'
  zone, Europe/Athens). Days are built from local midnights, so a window
  across a DST change is 23 or 25 hours long, never shifted.

  Parts of the day without days cover the next 14 days. Adjacent windows
  merge, so «σήμερα + αύριο» is one window.
  """

  @parts %{
    "morning" => {~T[05:00:00], ~T[12:00:00]},
    "midday" => {~T[12:00:00], ~T[17:00:00]},
    "evening" => {~T[17:00:00], :midnight}
  }
  @horizon_days 14

  @doc "The default zone of Greek boxes."
  def default_time_zone, do: "Europe/Athens"

  @doc "The local date of `now` in `time_zone`."
  def local_date(%DateTime{} = now, time_zone),
    do: now |> DateTime.shift_zone!(time_zone) |> DateTime.to_date()

  @doc """
  `nil` when neither days nor parts of the day are chosen, else a sorted list
  of `{from, to}` UTC DateTimes (from inclusive, to exclusive).
  """
  def windows(when_, date_from, date_to, times, now, time_zone \\ default_time_zone())

  def windows(nil, _date_from, _date_to, [], _now, _time_zone), do: nil

  def windows(when_, date_from, date_to, times, %DateTime{} = now, time_zone) do
    today = local_date(now, time_zone)

    for day <- days(when_, today, date_from, date_to),
        {starts, ends} <- spans(times) do
      {at(day, starts, time_zone), finish(day, ends, time_zone)}
    end
    |> Enum.sort_by(&DateTime.to_unix(elem(&1, 0), :microsecond))
    |> merge()
  end

  @doc "The days a `when` value covers, from the local `today`."
  def days("today", today, _from, _to), do: [today]
  def days("tomorrow", today, _from, _to), do: [Date.add(today, 1)]
  def days("week", today, _from, _to), do: Enum.map(0..6, &Date.add(today, &1))
  def days("range", _today, from, to), do: Enum.to_list(Date.range(from, to))
  def days(nil, today, _from, _to), do: Enum.map(0..(@horizon_days - 1), &Date.add(today, &1))

  # Saturday and Sunday: the coming ones, or what is left of this weekend.
  def days("weekend", today, _from, _to) do
    case Date.day_of_week(today) do
      6 -> [today, Date.add(today, 1)]
      7 -> [today]
      weekday -> [Date.add(today, 6 - weekday), Date.add(today, 7 - weekday)]
    end
  end

  defp spans([]), do: [{~T[00:00:00], :midnight}]
  defp spans(times), do: Enum.map(times, &Map.fetch!(@parts, &1))

  defp finish(day, :midnight, time_zone), do: at(Date.add(day, 1), ~T[00:00:00], time_zone)
  defp finish(day, time, time_zone), do: at(day, time, time_zone)

  # A wall-clock time that a DST change skips starts at the first instant
  # after the gap; one it repeats starts at its first occurrence.
  defp at(date, time, time_zone) do
    case DateTime.new(date, time, time_zone) do
      {:ok, datetime} -> utc(datetime)
      {:gap, _before, just_after} -> utc(just_after)
      {:ambiguous, first, _second} -> utc(first)
    end
  end

  defp utc(datetime), do: DateTime.shift_zone!(datetime, "Etc/UTC")

  defp merge([]), do: []

  defp merge([first | rest]) do
    rest
    |> Enum.reduce([first], fn {from, to}, [{last_from, last_to} | done] ->
      if DateTime.compare(from, last_to) != :gt,
        do: [{last_from, latest(to, last_to)} | done],
        else: [{from, to}, {last_from, last_to} | done]
    end)
    |> Enum.reverse()
  end

  defp latest(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
end
