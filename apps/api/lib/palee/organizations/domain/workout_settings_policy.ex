defmodule Palee.Organizations.Domain.WorkoutSettingsPolicy do
  @moduledoc """
  A gym's workout-authoring defaults, stored under
  `organization_settings.settings["workouts"]` (ADR-163).

  - `wod_goals_visible_by_default`: the starting value of the editor's
    «Εμφάνιση στόχων στα μέλη» toggle for a workout without goals of its own
    (off by default).
  """

  @settings_key "workouts"
  @defaults %{wod_goals_visible_by_default: false}

  def settings_key, do: @settings_key
  def defaults, do: @defaults

  @doc "The settings read from an organization settings map, with defaults."
  def from_settings(%{} = settings) do
    case Map.get(settings, @settings_key) do
      %{} = stored ->
        %{wod_goals_visible_by_default: Map.get(stored, "wod_goals_visible_by_default") == true}

      _missing ->
        @defaults
    end
  end

  def from_settings(_settings), do: @defaults

  @doc """
  Validates a partial update (string or atom keys) over `current`; returns
  the map to store (string keys) and the new settings.
  """
  def update(current, params) when is_map(current) and is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    case Map.fetch(params, "wod_goals_visible_by_default") do
      :error ->
        {:ok, stored(current), current}

      {:ok, value} when is_boolean(value) ->
        updated = %{current | wod_goals_visible_by_default: value}
        {:ok, stored(updated), updated}

      {:ok, _other} ->
        {:error, :bad_request}
    end
  end

  def update(_current, _params), do: {:error, :bad_request}

  defp stored(settings),
    do: %{"wod_goals_visible_by_default" => settings.wod_goals_visible_by_default}
end
