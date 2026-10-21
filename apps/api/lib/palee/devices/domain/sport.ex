defmodule Palee.Devices.Domain.Sport do
  @moduledoc """
  Garmin's activity types folded into the few sports the journal names
  (ADR-161). The client localizes the sport; the raw type is kept beside it.
  """

  @sports ~w(run ride swim walk hike strength cardio hiit yoga row ski other)

  @prefixes [
    {"TRAIL_RUNNING", "run"},
    {"TREADMILL_RUNNING", "run"},
    {"RUNNING", "run"},
    {"STREET_RUNNING", "run"},
    {"TRACK_RUNNING", "run"},
    {"VIRTUAL_RUN", "run"},
    {"INDOOR_RUNNING", "run"},
    {"CYCLING", "ride"},
    {"INDOOR_CYCLING", "ride"},
    {"ROAD_BIKING", "ride"},
    {"MOUNTAIN_BIKING", "ride"},
    {"GRAVEL_CYCLING", "ride"},
    {"VIRTUAL_RIDE", "ride"},
    {"LAP_SWIMMING", "swim"},
    {"OPEN_WATER_SWIMMING", "swim"},
    {"SWIMMING", "swim"},
    {"WALKING", "walk"},
    {"CASUAL_WALKING", "walk"},
    {"SPEED_WALKING", "walk"},
    {"HIKING", "hike"},
    {"STRENGTH_TRAINING", "strength"},
    {"INDOOR_CARDIO", "cardio"},
    {"FITNESS_EQUIPMENT", "cardio"},
    {"ELLIPTICAL", "cardio"},
    {"STAIR_CLIMBING", "cardio"},
    {"HIIT", "hiit"},
    {"BOOTCAMP", "hiit"},
    {"YOGA", "yoga"},
    {"PILATES", "yoga"},
    {"BREATHWORK", "yoga"},
    {"INDOOR_ROWING", "row"},
    {"ROWING", "row"},
    {"RESORT_SKIING", "ski"},
    {"BACKCOUNTRY_SKIING", "ski"},
    {"CROSS_COUNTRY_SKIING", "ski"},
    {"SKIING", "ski"}
  ]

  def sports, do: @sports

  def of(type) when is_binary(type) do
    upper = String.upcase(type)

    case Enum.find(@prefixes, fn {name, _sport} -> upper == name end) do
      {_name, sport} -> sport
      nil -> fuzzy(upper)
    end
  end

  def of(_type), do: "other"

  # Garmin adds new variants over time (`INDOOR_TRACK_RUNNING`, …).
  defp fuzzy(type) do
    cond do
      String.contains?(type, "RUN") -> "run"
      String.contains?(type, ["CYCL", "BIK", "RIDE"]) -> "ride"
      String.contains?(type, "SWIM") -> "swim"
      String.contains?(type, "WALK") -> "walk"
      String.contains?(type, "STRENGTH") -> "strength"
      String.contains?(type, "ROW") -> "row"
      String.contains?(type, "SKI") -> "ski"
      true -> "other"
    end
  end
end
