defmodule Palee.Organizations.Domain.WorkoutSettingsPolicy do
  @moduledoc """
  A gym's workout-authoring defaults, stored under
  `organization_settings.settings["workouts"]` (ADR-163).

  - `wod_goals_visible_by_default`: the starting value of the editor's
    «Εμφάνιση στόχων στα μέλη» toggle for a workout without goals of its own
    (off by default).
  - `wod_assistant_enabled` (ADR-180): whether coaches may use the WOD
    assistant at all. On by default, so gyms keep what they had; off, the
    assistant is never called and every new workout is written in text
    sections with a timer each.
  - `workout_types` (ADR-275): the workout kinds the gym's editors offer, or
    nil for every kind. A workout keeps its kind even when the gym hides it.
  """

  alias Palee.Workouts.Domain.WorkoutType

  @settings_key "workouts"
  @defaults %{
    wod_goals_visible_by_default: false,
    wod_assistant_enabled: true,
    workout_types: nil
  }
  @switches [:wod_goals_visible_by_default, :wod_assistant_enabled]

  def settings_key, do: @settings_key
  def defaults, do: @defaults

  @doc "The settings read from an organization settings map, with defaults."
  def from_settings(%{} = settings) do
    case Map.get(settings, @settings_key) do
      %{} = stored ->
        @switches
        |> Map.new(fn field ->
          {field, boolean(Map.get(stored, Atom.to_string(field)), Map.fetch!(@defaults, field))}
        end)
        |> Map.put(:workout_types, stored_types(Map.get(stored, "workout_types")))

      _missing ->
        @defaults
    end
  end

  def from_settings(_settings), do: @defaults

  @doc "Whether the gym lets coaches use the WOD assistant (ADR-180)."
  def wod_assistant_enabled?(settings), do: Map.get(settings, :wod_assistant_enabled, true)

  @doc "ADR-275: the kinds the gym's editors offer (every kind when the gym chose none)."
  def workout_types(settings), do: Map.get(settings, :workout_types) || WorkoutType.keys()

  @doc """
  Validates a partial update (string or atom keys) over `current`; returns
  the map to store (string keys) and the new settings.
  """
  def update(current, params) when is_map(current) and is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    current = Map.merge(@defaults, current)

    @switches
    |> Enum.reduce_while({:ok, current}, fn field, {:ok, acc} ->
      case Map.fetch(params, Atom.to_string(field)) do
        :error -> {:cont, {:ok, acc}}
        {:ok, value} when is_boolean(value) -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:ok, _other} -> {:halt, {:error, :bad_request}}
      end
    end)
    |> put_workout_types(params)
    |> case do
      {:ok, updated} -> {:ok, stored(updated), updated}
      error -> error
    end
  end

  def update(_current, _params), do: {:error, :bad_request}

  defp put_workout_types({:ok, settings}, params) do
    case Map.fetch(params, "workout_types") do
      :error -> {:ok, settings}
      {:ok, nil} -> {:ok, Map.put(settings, :workout_types, nil)}
      {:ok, types} -> chosen_types(types, settings)
    end
  end

  defp put_workout_types(error, _params), do: error

  # At least one kind, every one known; kept in the catalogue's order.
  defp chosen_types(types, settings) when is_list(types) and types != [] do
    if Enum.all?(types, &(is_binary(&1) and WorkoutType.valid?(&1))),
      do:
        {:ok, Map.put(settings, :workout_types, Enum.filter(WorkoutType.keys(), &(&1 in types)))},
      else: {:error, :bad_request}
  end

  defp chosen_types(_types, _settings), do: {:error, :bad_request}

  # Kinds stored before the catalogue dropped one are skipped; none left means every kind.
  defp stored_types(types) when is_list(types) do
    case Enum.filter(WorkoutType.keys(), &(&1 in types)) do
      [] -> nil
      known -> known
    end
  end

  defp stored_types(_types), do: nil

  defp boolean(value, _default) when is_boolean(value), do: value
  defp boolean(_value, default), do: default

  defp stored(settings) do
    @switches
    |> Map.new(&{Atom.to_string(&1), Map.fetch!(settings, &1)})
    |> Map.put("workout_types", Map.get(settings, :workout_types))
  end
end
