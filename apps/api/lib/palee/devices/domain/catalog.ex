defmodule Palee.Devices.Domain.Catalog do
  @moduledoc """
  The vocabulary of connected devices (ADR-161, ADR-172): providers,
  connection states, what can be synced, how far back history goes, and
  what an import can become. Pure data and validation.
  """

  @providers ~w(garmin apple_health health_connect)
  # ADR-172: the phone's own health store, read by the store apps.
  @phone_providers ~w(apple_health health_connect)
  @statuses ~w(pending active error revoked)
  @import_kinds ~w(activity sleep weight daily steps)
  @import_statuses ~w(imported merged needs_confirmation ignored)
  @target_types ~w(device_activity wellness_entry body_snapshot daily_stat)
  @activity_states ~w(own merged pending)
  @merge_kinds ~w(training_log execution)
  @backfill_days [0, 30, 90]
  @backfill_statuses ~w(none running done failed)

  # Board 16, Q1 (A): everything on by default, each switchable. The phone
  # also counts steps (ADR-172); Garmin's choices stay the four it had.
  @garmin_pref_keys ~w(activities sleep weight resting_hr)
  @phone_pref_keys ~w(activities sleep weight resting_hr steps)
  @pref_of_kind %{
    "activity" => "activities",
    "sleep" => "sleep",
    "weight" => "weight",
    "daily" => "resting_hr",
    "steps" => "steps"
  }

  # Kinds that describe a day or a night rather than one sample: a later
  # import with the same id replaces what the earlier one set (a day's steps
  # keep growing; a night's last segments arrive after waking).
  @replaceable_kinds ~w(sleep daily steps)

  def providers, do: @providers
  def phone_providers, do: @phone_providers
  def phone_provider?(provider), do: provider in @phone_providers
  def statuses, do: @statuses
  def import_kinds, do: @import_kinds
  def import_statuses, do: @import_statuses
  def target_types, do: @target_types
  def activity_states, do: @activity_states
  def merge_kinds, do: @merge_kinds
  def backfill_days, do: @backfill_days
  def backfill_statuses, do: @backfill_statuses
  def replaceable_kind?(kind), do: kind in @replaceable_kinds

  @doc "The sync choices a provider offers (Garmin's when none is named)."
  def pref_keys, do: @garmin_pref_keys
  def pref_keys(provider) when provider in @phone_providers, do: @phone_pref_keys
  def pref_keys(_provider), do: @garmin_pref_keys

  def default_prefs, do: default_prefs("garmin")
  def default_prefs(provider), do: Map.new(pref_keys(provider), &{&1, true})

  @doc "Board 16, Q5 (A): «Τελευταίες 30 μέρες» is preselected."
  def default_backfill_days, do: 30

  # Sleep, weight, resting heart rate and steps are health data (plan D8,
  # ADR-172); a workout is training data and syncs without the consent.
  @health_pref_keys ~w(sleep weight resting_hr steps)

  @doc "Whether `prefs` bring in health data, among the choices `provider` offers."
  def health_data?(prefs), do: health_data?("garmin", prefs)

  def health_data?(provider, prefs) when is_map(prefs) do
    provider
    |> pref_keys()
    |> Enum.filter(&(&1 in @health_pref_keys))
    |> Enum.any?(&(Map.get(prefs, &1, true) != false))
  end

  @doc "The sync preference that lets an import kind in."
  def pref_of_kind(kind), do: Map.fetch!(@pref_of_kind, kind)

  @doc "Whether `prefs` lets imports of `kind` in (unknown keys count as on)."
  def wanted?(prefs, kind) when is_map(prefs),
    do: Map.get(prefs, pref_of_kind(kind), true) != false

  @doc """
  Validates a change to the sync preferences against the stored ones: only
  the provider's keys, booleans only. Returns the full map.
  """
  def merge_prefs(current, changes), do: merge_prefs("garmin", current, changes)

  def merge_prefs(provider, current, nil),
    do: {:ok, provider |> default_prefs() |> Map.merge(current || %{})}

  def merge_prefs(provider, current, changes) when is_map(changes) do
    changes = Map.new(changes, fn {key, value} -> {to_string(key), value} end)
    keys = pref_keys(provider)

    cond do
      Enum.any?(Map.keys(changes), &(&1 not in keys)) ->
        {:error, :invalid_sync_prefs}

      Enum.any?(Map.values(changes), &(not is_boolean(&1))) ->
        {:error, :invalid_sync_prefs}

      true ->
        {:ok, provider |> default_prefs() |> Map.merge(current || %{}) |> Map.merge(changes)}
    end
  end

  def merge_prefs(_provider, _current, _changes), do: {:error, :invalid_sync_prefs}

  def validate_backfill_days(nil), do: {:ok, default_backfill_days()}
  def validate_backfill_days(days) when days in @backfill_days, do: {:ok, days}

  def validate_backfill_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {days, ""} -> validate_backfill_days(days)
      _invalid -> {:error, :invalid_backfill_days}
    end
  end

  def validate_backfill_days(_days), do: {:error, :invalid_backfill_days}
end
