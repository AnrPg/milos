defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Preflight do
  @moduledoc """
  Pure publication preflight for parsed Quick Text workouts.

  It revalidates every canonical section, item group, scale reference, and
  timer configuration independently of the parser so publication never relies
  on a single validation layer.
  """

  alias MilosTraining.Workouts.Domain.{TimerConfig, WorkoutSetComposer}

  def validate(workout, active_scale_slugs) when is_map(workout) do
    with :ok <- validate_identity(workout),
         :ok <- validate_sections(value(workout, :sections, []), MapSet.new(active_scale_slugs)) do
      :ok
    end
  end

  def validate(_workout, _active_scale_slugs), do: {:error, :invalid_canonical_workout}

  defp validate_identity(workout) do
    cond do
      blank?(value(workout, :title)) -> {:error, :missing_workout_title}
      blank?(value(workout, :type)) -> {:error, :missing_workout_type}
      true -> :ok
    end
  end

  defp validate_sections([], _active_scale_slugs), do: {:error, :no_sections}

  defp validate_sections(sections, active_scale_slugs) when is_list(sections) do
    Enum.reduce_while(sections, :ok, fn section, :ok ->
      with {:ok, _timer_config} <- TimerConfig.normalize(value(section, :timer_config)),
           {:ok, items} <- WorkoutSetComposer.normalize_items(value(section, :exercises, [])),
           :ok <- validate_exercises(items, active_scale_slugs),
           :ok <- validate_optional_children(value(section, :sections, []), active_scale_slugs) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_sections(_sections, _active_scale_slugs), do: {:error, :invalid_sections}

  defp validate_optional_children([], _active_scale_slugs), do: :ok

  defp validate_optional_children(children, active_scale_slugs),
    do: validate_sections(children, active_scale_slugs)

  defp validate_exercises(items, active_scale_slugs) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      variations = value(item, :variations, [])

      case Enum.find(variations, fn variation ->
             slug = value(variation, :scale_level_slug) || value(variation, :scale_level)
             blank?(slug) or not MapSet.member?(active_scale_slugs, slug)
           end) do
        nil ->
          {:cont, :ok}

        variation ->
          {:halt, {:error, {:unknown_scale_level, value(variation, :scale_level_slug)}}}
      end
    end)
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
