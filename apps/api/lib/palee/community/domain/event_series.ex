defmodule Palee.Community.Domain.EventSeries do
  @moduledoc """
  «Επανάληψη κάθε εβδομάδα» (ADR-153): an event repeated weekly until a date
  is one event per week, at the same local time in the box's time zone (so
  it stays at 19:00 across a daylight-saving change), at most
  #{26} occurrences. Pure.

  Editing «this and following» moves every following occurrence the way the
  edited one moved: by the same number of days, to the same new local time,
  with the same new length.
  """

  @max_occurrences 26

  def max_occurrences, do: @max_occurrences

  @doc """
  The occurrences of a weekly event from `starts_at` until `until` (a date,
  inclusive, in the box's zone): `{:ok, [{starts_at, ends_at}]}`.
  """
  def weekly(%DateTime{} = starts_at, %DateTime{} = ends_at, %Date{} = until, zone) do
    local = to_local(starts_at, zone)
    first = DateTime.to_date(local)
    duration = DateTime.diff(ends_at, starts_at, :microsecond)

    if Date.compare(until, first) == :lt do
      {:error, :invalid_repeat}
    else
      occurrences =
        0..(@max_occurrences - 1)
        |> Stream.map(&Date.add(first, &1 * 7))
        |> Stream.take_while(&(Date.compare(&1, until) != :gt))
        |> Enum.map(fn date ->
          start = at_local(date, DateTime.to_time(local), zone)
          {start, DateTime.add(start, duration, :microsecond)}
        end)

      {:ok, occurrences}
    end
  end

  @doc """
  New times for `occurrence` when the occurrence it follows moved from
  `earlier` to `later` (maps with `starts_at` and `ends_at`).
  """
  def follow(occurrence, earlier, later, zone) do
    if same_times?(earlier, later) do
      %{starts_at: occurrence.starts_at, ends_at: occurrence.ends_at}
    else
      days =
        Date.diff(
          DateTime.to_date(to_local(later.starts_at, zone)),
          DateTime.to_date(to_local(earlier.starts_at, zone))
        )

      time = later.starts_at |> to_local(zone) |> DateTime.to_time()
      duration = DateTime.diff(later.ends_at, later.starts_at, :microsecond)
      date = occurrence.starts_at |> to_local(zone) |> DateTime.to_date() |> Date.add(days)
      start = at_local(date, time, zone)

      %{starts_at: start, ends_at: DateTime.add(start, duration, :microsecond)}
    end
  end

  defp same_times?(earlier, later),
    do:
      DateTime.compare(earlier.starts_at, later.starts_at) == :eq and
        DateTime.compare(earlier.ends_at, later.ends_at) == :eq

  defp to_local(at, zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> local
      {:error, _reason} -> at
    end
  end

  defp at_local(date, time, zone) do
    case DateTime.new(date, time, zone) do
      {:ok, local} -> utc(local)
      {:gap, _before, after_gap} -> utc(after_gap)
      {:ambiguous, first, _second} -> utc(first)
      {:error, _reason} -> date |> DateTime.new!(time, "Etc/UTC")
    end
  end

  defp utc(local), do: DateTime.shift_zone!(local, "Etc/UTC")
end
