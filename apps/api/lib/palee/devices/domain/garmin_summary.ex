defmodule Palee.Devices.Domain.GarminSummary do
  @moduledoc """
  Reads the summaries the Garmin Health and Activity APIs send (ADR-161):
  each push or callback batch is a JSON object keyed by summary type
  (`activities`, `sleeps`, `bodyComps`, `dailies`, …), every summary naming
  its Garmin `userId` and `summaryId`. This module turns one summary into
  the normalized facts Palee keeps, trims the payload kept for audit, and
  says which import kind a summary type is. Pure: times come from the
  summary itself (epoch seconds plus the local offset).
  """

  alias Palee.Devices.Domain.{LocalTime, Sport}

  @kinds %{
    "activities" => "activity",
    "manuallyUpdatedActivities" => "activity",
    "sleeps" => "sleep",
    "bodyComps" => "weight",
    "dailies" => "daily"
  }

  # What is kept of each summary in `device_imports.payload`: enough to audit
  # and to re-import, nothing else Garmin sends (GPS samples, device serials).
  @kept %{
    "activity" => ~w(summaryId activityId activityName activityType startTimeInSeconds
                     startTimeOffsetInSeconds durationInSeconds distanceInMeters
                     averageHeartRateInBeatsPerMinute maxHeartRateInBeatsPerMinute
                     activeKilocalories deviceName manual),
    "sleep" => ~w(summaryId calendarDate startTimeInSeconds startTimeOffsetInSeconds
                  durationInSeconds deepSleepDurationInSeconds lightSleepDurationInSeconds
                  remSleepInSeconds awakeDurationInSeconds overallSleepScore validation),
    "weight" => ~w(summaryId measurementTimeInSeconds measurementTimeOffsetInSeconds
                   weightInGrams bodyFatInPercent),
    "daily" => ~w(summaryId calendarDate startTimeInSeconds startTimeOffsetInSeconds
                  restingHeartRateInBeatsPerMinute)
  }

  @doc "Summary types this integration reads, as the push body names them."
  def summary_types, do: Map.keys(@kinds)

  @doc "The import kind of a summary type, or nil for types Palee ignores."
  def kind(type), do: Map.get(@kinds, type)

  @doc "The summary types to ask a backfill for, given the sync preferences' kinds."
  def backfill_types(kinds),
    do: for({type, kind} <- @kinds, kind in kinds, type != "manuallyUpdatedActivities", do: type)

  def user_id(%{"userId" => user_id}) when is_binary(user_id) and user_id != "", do: user_id
  def user_id(_summary), do: nil

  @doc "The provider's id of a summary, unique per kind."
  def provider_id(summary) do
    case summary["summaryId"] || summary["activityId"] do
      nil -> nil
      id -> to_string(id)
    end
  end

  def trim(kind, summary), do: Map.take(summary, Map.fetch!(@kept, kind))

  @doc "A workout: what the journal shows of it."
  def activity(summary) do
    with {:ok, started_at} <- instant(summary["startTimeInSeconds"]),
         duration when is_integer(duration) and duration >= 0 <-
           integer(summary["durationInSeconds"]) || {:error, :missing_duration} do
      offset = integer(summary["startTimeOffsetInSeconds"]) || 0
      type = summary["activityType"]

      {:ok,
       %{
         provider_id: provider_id(summary),
         activity_type: type,
         sport: Sport.of(type),
         title: title(summary["activityName"]),
         started_at: started_at,
         started_tz: LocalTime.zone(offset),
         local_date: LocalTime.date(started_at, offset),
         duration_seconds: duration,
         distance_meters: number(summary["distanceInMeters"]),
         avg_heart_rate: heart_rate(summary["averageHeartRateInBeatsPerMinute"]),
         max_heart_rate: heart_rate(summary["maxHeartRateInBeatsPerMinute"]),
         calories: integer(summary["activeKilocalories"])
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_duration}
    end
  end

  @doc """
  A night: bedtime, wake time and quality, on the day it ends (Garmin's
  `calendarDate`). Quality 1–5 comes from the sleep score's qualifier.
  """
  def sleep(summary) do
    with {:ok, bed_at} <- instant(summary["startTimeInSeconds"]),
         duration when is_integer(duration) and duration > 0 <-
           integer(summary["durationInSeconds"]) || {:error, :missing_duration} do
      offset = integer(summary["startTimeOffsetInSeconds"]) || 0
      wake_at = DateTime.add(bed_at, duration, :second)

      {:ok,
       %{
         provider_id: provider_id(summary),
         bed_at: bed_at,
         wake_at: wake_at,
         tz: LocalTime.zone(offset),
         on: date(summary["calendarDate"]) || LocalTime.date(wake_at, offset),
         quality: quality(summary["overallSleepScore"])
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_duration}
    end
  end

  @doc "A weigh-in on a Garmin scale: kilograms and, when measured, body fat."
  def weight(summary) do
    with {:ok, taken_at} <- instant(summary["measurementTimeInSeconds"]),
         grams when is_number(grams) and grams > 0 <-
           number(summary["weightInGrams"]) || {:error, :missing_weight} do
      offset = integer(summary["measurementTimeOffsetInSeconds"]) || 0
      fat = number(summary["bodyFatInPercent"])

      metrics =
        %{"weight" => Float.round(grams / 1000, 2)}
        |> then(&if(is_number(fat) and fat > 0, do: Map.put(&1, "body_fat", fat * 1.0), else: &1))

      {:ok,
       %{
         provider_id: provider_id(summary),
         taken_at: taken_at,
         tz: LocalTime.zone(offset),
         on: LocalTime.date(taken_at, offset),
         metrics: metrics
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :missing_weight}
    end
  end

  @doc "A day's summary: only the resting heart rate is kept (Πρόοδος)."
  def daily(summary) do
    offset = integer(summary["startTimeOffsetInSeconds"]) || 0

    on =
      date(summary["calendarDate"]) ||
        case instant(summary["startTimeInSeconds"]) do
          {:ok, at} -> LocalTime.date(at, offset)
          _missing -> nil
        end

    case {on, heart_rate(summary["restingHeartRateInBeatsPerMinute"])} do
      {nil, _rate} -> {:error, :missing_date}
      {_on, nil} -> {:error, :missing_resting_heart_rate}
      {on, rate} -> {:ok, %{provider_id: provider_id(summary), on: on, resting_heart_rate: rate}}
    end
  end

  @qualifiers %{"EXCELLENT" => 5, "GOOD" => 4, "FAIR" => 3, "POOR" => 2}

  defp quality(%{"qualifierKey" => key}) when is_map_key(@qualifiers, key),
    do: Map.fetch!(@qualifiers, key)

  defp quality(%{"value" => value}) when is_number(value) do
    cond do
      value >= 90 -> 5
      value >= 80 -> 4
      value >= 60 -> 3
      value >= 40 -> 2
      true -> 1
    end
  end

  defp quality(_score), do: nil

  defp title(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> String.slice(name, 0, 160)
    end
  end

  defp title(_name), do: nil

  defp instant(seconds) when is_integer(seconds) and seconds > 0,
    do: {:ok, DateTime.from_unix!(seconds * 1_000_000, :microsecond)}

  defp instant(_seconds), do: {:error, :missing_start}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _invalid -> nil
    end
  end

  defp date(_value), do: nil

  defp heart_rate(value) do
    case integer(value) do
      rate when is_integer(rate) and rate >= 20 and rate <= 260 -> rate
      _other -> nil
    end
  end

  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_float(value), do: round(value)
  defp integer(_value), do: nil

  defp number(value) when is_number(value) and value >= 0, do: value * 1.0
  defp number(_value), do: nil
end
