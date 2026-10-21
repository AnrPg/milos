defmodule MilosTraining.Devices.Domain.Catalog do
  @moduledoc """
  The vocabulary of connected devices (ADR-161): providers, connection
  states, what can be synced, how far back history goes, and what an import
  can become. Pure data and validation.
  """

  @providers ~w(garmin apple_health health_connect)
  @statuses ~w(pending active error revoked)
  @import_kinds ~w(activity sleep weight daily)
  @import_statuses ~w(imported merged needs_confirmation ignored)
  @target_types ~w(device_activity wellness_entry body_snapshot daily_stat)
  @activity_states ~w(own merged pending)
  @merge_kinds ~w(training_log execution)
  @backfill_days [0, 30, 90]
  @backfill_statuses ~w(none running done failed)

  # Board 16, Q1 (A): everything on by default, each switchable.
  @pref_keys ~w(activities sleep weight resting_hr)
  @default_prefs Map.new(@pref_keys, &{&1, true})
  @pref_of_kind %{
    "activity" => "activities",
    "sleep" => "sleep",
    "weight" => "weight",
    "daily" => "resting_hr"
  }

  def providers, do: @providers
  def statuses, do: @statuses
  def import_kinds, do: @import_kinds
  def import_statuses, do: @import_statuses
  def target_types, do: @target_types
  def activity_states, do: @activity_states
  def merge_kinds, do: @merge_kinds
  def backfill_days, do: @backfill_days
  def backfill_statuses, do: @backfill_statuses
  def pref_keys, do: @pref_keys
  def default_prefs, do: @default_prefs

  @doc "Board 16, Q5 (A): «Τελευταίες 30 μέρες» is preselected."
  def default_backfill_days, do: 30

  @doc "The sync preference that lets an import kind in."
  def pref_of_kind(kind), do: Map.fetch!(@pref_of_kind, kind)

  @doc "Whether `prefs` lets imports of `kind` in (unknown keys count as on)."
  def wanted?(prefs, kind) when is_map(prefs),
    do: Map.get(prefs, pref_of_kind(kind), true) != false

  @doc """
  Validates a change to the sync preferences against the stored ones: only
  known keys, booleans only. Returns the full map.
  """
  def merge_prefs(current, nil), do: {:ok, Map.merge(@default_prefs, current || %{})}

  def merge_prefs(current, changes) when is_map(changes) do
    changes = Map.new(changes, fn {key, value} -> {to_string(key), value} end)

    cond do
      Enum.any?(Map.keys(changes), &(&1 not in @pref_keys)) ->
        {:error, :invalid_sync_prefs}

      Enum.any?(Map.values(changes), &(not is_boolean(&1))) ->
        {:error, :invalid_sync_prefs}

      true ->
        {:ok, @default_prefs |> Map.merge(current || %{}) |> Map.merge(changes)}
    end
  end

  def merge_prefs(_current, _changes), do: {:error, :invalid_sync_prefs}

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
