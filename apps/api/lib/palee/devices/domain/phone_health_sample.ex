defmodule Palee.Devices.Domain.PhoneHealthSample do
  @moduledoc """
  Reads what the store apps send from Apple Health or Health Connect
  (ADR-172). The app's health plugin reads the phone's store and the web
  layer shapes it into one provider-neutral batch:

      %{
        "activities" => [%{"id", "type", "title", "start", "end",
                           "distance_m", "avg_hr", "max_hr", "source_app"}],
        "sleeps" => [%{"id", "start", "end"}],
        "weights" => [%{"id", "at", "kg"}],
        "dailies" => [%{"date", "resting_hr", "steps"}]
      }

  Instants are ISO 8601 with the wearer's offset then (`+03:00`), so the
  local day and the fixed zone come from the record itself, as with Garmin.
  This module turns one record into the same facts `GarminSummary` gives
  (so the import rules are shared), names its dedupe id and trims what is
  kept for audit. Pure: nothing here reads the clock.
  """

  alias Palee.Devices.Domain.{LocalTime, Sport}

  @max_per_list 500
  @max_activity_seconds 24 * 3600
  @min_sleep_seconds 30 * 60
  @max_sleep_seconds 20 * 3600

  @kept %{
    "activity" => ~w(id type title start end distance_m avg_hr max_hr source_app),
    "sleep" => ~w(id start end),
    "weight" => ~w(id at kg),
    "daily" => ~w(date resting_hr),
    "steps" => ~w(date steps)
  }

  def max_per_list, do: @max_per_list

  @doc """
  The batch as `{kind, records}` pairs, in import order. A day's resting
  heart rate and its steps become separate imports (`daily`, `steps`), so
  each follows its own sync choice. More than #{@max_per_list} records in a
  list is refused (the app sends in chunks).
  """
  def batches(body) when is_map(body) do
    lists = %{
      "activity" => list(body, "activities"),
      "sleep" => list(body, "sleeps"),
      "weight" => list(body, "weights"),
      "dailies" => list(body, "dailies")
    }

    if Enum.any?(lists, fn {_key, records} -> length(records) > @max_per_list end) do
      {:error, :phone_health_batch_too_large}
    else
      dailies = lists["dailies"]

      {:ok,
       [
         {"activity", lists["activity"]},
         {"sleep", lists["sleep"]},
         {"weight", lists["weight"]},
         {"daily", Enum.filter(dailies, &present?(&1["resting_hr"]))},
         {"steps", Enum.filter(dailies, &present?(&1["steps"]))}
       ]
       |> Enum.reject(fn {_kind, records} -> records == [] end)}
    end
  end

  def batches(_body), do: {:error, :invalid_phone_health_batch}

  @doc "The phone's id of a record, unique per kind (a day for daily kinds)."
  def provider_id(kind, record) when kind in ["daily", "steps"], do: date_id(record["date"])

  def provider_id(_kind, %{"id" => id}) when is_binary(id) and id != "",
    do: String.slice(id, 0, 120)

  def provider_id(_kind, _record), do: nil

  def trim(kind, record), do: Map.take(record, Map.fetch!(@kept, kind))

  @doc "A workout: what the journal shows of it."
  def activity(record) do
    with {:ok, started_at, offset} <- instant(record["start"], :missing_start),
         {:ok, ended_at, _offset} <- instant(record["end"], :missing_duration),
         duration when duration > 0 and duration <= @max_activity_seconds <-
           DateTime.diff(ended_at, started_at, :second) do
      type = text(record["type"], 80)

      {:ok,
       %{
         provider_id: provider_id("activity", record),
         activity_type: type,
         sport: Sport.of(type),
         title: text(record["title"], 160),
         started_at: started_at,
         started_tz: LocalTime.zone(offset),
         local_date: LocalTime.date(started_at, offset),
         duration_seconds: duration,
         distance_meters: distance(record["distance_m"]),
         avg_heart_rate: heart_rate(record["avg_hr"]),
         max_heart_rate: heart_rate(record["max_hr"]),
         calories: nil
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_duration}
    end
  end

  @doc "A night: bedtime and wake time, on the day it ends. Phones give no quality."
  def sleep(record) do
    with {:ok, bed_at, _offset} <- instant(record["start"], :missing_start),
         {:ok, wake_at, offset} <- instant(record["end"], :missing_duration),
         duration when duration >= @min_sleep_seconds and duration <= @max_sleep_seconds <-
           DateTime.diff(wake_at, bed_at, :second) do
      {:ok,
       %{
         provider_id: provider_id("sleep", record),
         bed_at: bed_at,
         wake_at: wake_at,
         tz: LocalTime.zone(offset),
         on: LocalTime.date(wake_at, offset),
         quality: nil
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_duration}
    end
  end

  @doc "A weigh-in, in kilograms."
  def weight(record) do
    with {:ok, taken_at, offset} <- instant(record["at"], :missing_start),
         kg when is_number(kg) and kg >= 20 and kg <= 400 <-
           record["kg"] || {:error, :missing_weight} do
      {:ok,
       %{
         provider_id: provider_id("weight", record),
         taken_at: taken_at,
         tz: LocalTime.zone(offset),
         on: LocalTime.date(taken_at, offset),
         metrics: %{"weight" => Float.round(kg * 1.0, 2)}
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_weight}
    end
  end

  @doc "A day's resting heart rate."
  def daily(record) do
    case {date(record["date"]), resting(record["resting_hr"])} do
      {nil, _rate} ->
        {:error, :missing_date}

      {_on, nil} ->
        {:error, :missing_resting_heart_rate}

      {on, rate} ->
        {:ok, %{provider_id: date_id(record["date"]), on: on, resting_heart_rate: rate}}
    end
  end

  @doc "A day's steps (the phone already merged phone and watch counts)."
  def steps(record) do
    case {date(record["date"]), record["steps"]} do
      {nil, _steps} ->
        {:error, :missing_date}

      {on, steps} when is_integer(steps) and steps >= 0 and steps <= 200_000 ->
        {:ok, %{provider_id: date_id(record["date"]), on: on, steps: steps}}

      {on, steps} when is_float(steps) and steps >= 0 and steps <= 200_000 ->
        {:ok, %{provider_id: date_id(record["date"]), on: on, steps: round(steps)}}

      _invalid ->
        {:error, :missing_steps}
    end
  end

  defp list(body, key) do
    case Map.get(body, key) do
      items when is_list(items) -> Enum.filter(items, &is_map/1)
      _other -> []
    end
  end

  defp present?(value), do: is_number(value)

  defp instant(value, missing) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, offset} -> {:ok, DateTime.truncate(at, :second), offset}
      _invalid -> {:error, missing}
    end
  end

  defp instant(_value, missing), do: {:error, missing}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _invalid -> nil
    end
  end

  defp date(_value), do: nil

  defp date_id(value) do
    case date(value) do
      nil -> nil
      date -> Date.to_iso8601(date)
    end
  end

  defp text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil

  defp distance(value) when is_number(value) and value > 0 and value < 1_000_000, do: value * 1.0
  defp distance(_value), do: nil

  defp heart_rate(value) when is_number(value) and value >= 20 and value <= 260, do: round(value)
  defp heart_rate(_value), do: nil

  defp resting(value) when is_number(value) and value >= 20 and value <= 200, do: round(value)
  defp resting(_value), do: nil
end
