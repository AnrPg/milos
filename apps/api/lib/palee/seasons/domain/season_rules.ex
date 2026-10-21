defmodule Palee.Seasons.Domain.SeasonRules do
  @moduledoc """
  What a season is and what it allows (ADR-167). Pure: callers pass today's
  date in the gym's time zone.

  A season runs from `starts_on` for `weeks` whole weeks. Its stored status is
  what staff chose (`draft`, `published`, `cancelled`); `running` and
  `completed` follow from the dates, so every read is right even before the
  daily sweep writes them down.

  Places: an active participant and an open request both hold one. A request
  that finds every place held waits on the waitlist; when a place frees, the
  earliest waiting request becomes a request again (staff still confirm it).
  """

  @statuses ~w(draft published running completed cancelled)
  @live ~w(published running)
  @max_programme_items 400

  def statuses, do: @statuses

  @doc "The last day of the season."
  def ends_on(%Date{} = starts_on, weeks) when is_integer(weeks) and weeks > 0,
    do: Date.add(starts_on, weeks * 7 - 1)

  def ends_on(%{starts_on: starts_on, weeks: weeks}), do: ends_on(starts_on, weeks)

  @doc "The status as of `today`."
  def effective_status(%{status: status}, _today) when status in ["draft", "cancelled"],
    do: status

  def effective_status(%{status: _status} = offering, %Date{} = today) do
    cond do
      Date.compare(today, ends_on(offering)) == :gt -> "completed"
      Date.compare(today, offering.starts_on) != :lt -> "running"
      true -> "published"
    end
  end

  @doc "Whether members see the season and may ask for a place."
  def open?(offering, today), do: effective_status(offering, today) in @live

  @doc "Whether the gym has published the season and it has not ended or been cancelled."
  def live?(offering, today), do: open?(offering, today)

  @doc """
  The status a new request gets: `requested` while a place is free (held =
  active participants + open requests), else `waitlisted`.
  """
  def request_status(capacity, held) when held < capacity, do: "requested"
  def request_status(_capacity, _held), do: "waitlisted"

  @doc "Whether staff may confirm one more participant."
  def can_confirm?(capacity, active), do: active < capacity

  @doc """
  Checks a request against the season: it must be live (published or
  running) as of today.
  """
  def request_check(offering, today) do
    if open?(offering, today), do: :ok, else: {:error, :season_not_open}
  end

  @doc """
  Whether the date-bound parts (start, weeks, programme) may still change:
  only while nobody is an active participant, so a confirmed programme never
  moves under a member.
  """
  def schedule_locked?(active_count), do: active_count > 0

  @doc "Fields that touch the schedule."
  def schedule_fields, do: ~w(starts_on weeks programme)a

  @doc """
  Validates and orders a programme: a list of `%{day, workout_id}` with each
  day inside the season (`0..weeks*7-1`) and no workout twice on one day.
  Returns `{:ok, [%{"day" => day, "workout_id" => id}]}` or `{:error, message}`.
  """
  def normalize_programme(items, weeks) when is_list(items) do
    with {:ok, parsed} <- parse_items(items),
         :ok <- within_season(parsed, weeks),
         :ok <- no_duplicates(parsed),
         :ok <- not_too_long(parsed) do
      {:ok,
       parsed
       |> Enum.sort_by(&{&1.day, &1.workout_id})
       |> Enum.map(&%{"day" => &1.day, "workout_id" => &1.workout_id})}
    end
  end

  def normalize_programme(_items, _weeks), do: {:error, "must be a list"}

  @doc """
  The programme's dated workouts from `from` on (a member confirmed during
  the season starts from today, not from day 0): `[{date, workout_id}]`.
  """
  def schedule(programme, %Date{} = starts_on, %Date{} = from) do
    programme
    |> Enum.map(fn item -> {Date.add(starts_on, day(item)), workout_id(item)} end)
    |> Enum.reject(fn {date, _workout_id} -> Date.compare(date, from) == :lt end)
  end

  @doc "The distinct workouts a programme uses."
  def programme_workout_ids(programme),
    do: programme |> Enum.map(&workout_id/1) |> Enum.uniq()

  defp parse_items(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case {day(item), workout_id(item)} do
        {day, workout_id} when is_integer(day) and is_binary(workout_id) ->
          {:cont, {:ok, [%{day: day, workout_id: workout_id} | acc]}}

        _other ->
          {:halt, {:error, "each item needs a day and a workout"}}
      end
    end)
  end

  defp within_season(_parsed, weeks) when not is_integer(weeks), do: :ok

  defp within_season(parsed, weeks) do
    last = weeks * 7 - 1

    if Enum.all?(parsed, &(&1.day >= 0 and &1.day <= last)),
      do: :ok,
      else: {:error, "every day must fall inside the season"}
  end

  defp no_duplicates(parsed) do
    if length(Enum.uniq(parsed)) == length(parsed),
      do: :ok,
      else: {:error, "a workout appears twice on one day"}
  end

  defp not_too_long(parsed) do
    if length(parsed) <= @max_programme_items,
      do: :ok,
      else: {:error, "at most #{@max_programme_items} workouts"}
  end

  defp day(%{"day" => day}), do: to_integer(day)
  defp day(%{day: day}), do: to_integer(day)
  defp day(_item), do: nil

  defp workout_id(%{"workout_id" => id}) when is_binary(id), do: id
  defp workout_id(%{workout_id: id}) when is_binary(id), do: id
  defp workout_id(_item), do: nil

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp to_integer(_value), do: nil
end
