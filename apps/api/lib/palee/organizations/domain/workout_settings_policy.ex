defmodule Palee.Organizations.Domain.WorkoutSettingsPolicy do
  @moduledoc """
  A gym's workout-authoring defaults, stored under
  `organization_settings.settings["workouts"]` (ADR-163).

  - `wod_goals_visible_by_default`: the starting value of the editor's
    «Εμφάνιση στόχων στα μέλη» toggle for a workout without goals of its own
    (off by default).
  - `wod_assistant_enabled` (ADR-179): whether coaches may use the WOD
    assistant at all. On by default, so gyms keep what they had; off, the
    assistant is never called and every new workout is written in text
    sections with a timer each.
  """

  @settings_key "workouts"
  @defaults %{wod_goals_visible_by_default: false, wod_assistant_enabled: true}
  @switches [:wod_goals_visible_by_default, :wod_assistant_enabled]

  def settings_key, do: @settings_key
  def defaults, do: @defaults

  @doc "The settings read from an organization settings map, with defaults."
  def from_settings(%{} = settings) do
    case Map.get(settings, @settings_key) do
      %{} = stored ->
        Map.new(@switches, fn field ->
          {field, boolean(Map.get(stored, Atom.to_string(field)), Map.fetch!(@defaults, field))}
        end)

      _missing ->
        @defaults
    end
  end

  def from_settings(_settings), do: @defaults

  @doc "Whether the gym lets coaches use the WOD assistant (ADR-179)."
  def wod_assistant_enabled?(settings), do: Map.get(settings, :wod_assistant_enabled, true)

  @doc """
  Validates a partial update (string or atom keys) over `current`; returns
  the map to store (string keys) and the new settings.
  """
  def update(current, params) when is_map(current) and is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    current = Map.merge(@defaults, current)

    Enum.reduce_while(@switches, {:ok, current}, fn field, {:ok, acc} ->
      case Map.fetch(params, Atom.to_string(field)) do
        :error -> {:cont, {:ok, acc}}
        {:ok, value} when is_boolean(value) -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:ok, _other} -> {:halt, {:error, :bad_request}}
      end
    end)
    |> case do
      {:ok, updated} -> {:ok, stored(updated), updated}
      error -> error
    end
  end

  def update(_current, _params), do: {:error, :bad_request}

  defp boolean(value, _default) when is_boolean(value), do: value
  defp boolean(_value, default), do: default

  defp stored(settings), do: Map.new(@switches, &{Atom.to_string(&1), Map.fetch!(settings, &1)})
end
