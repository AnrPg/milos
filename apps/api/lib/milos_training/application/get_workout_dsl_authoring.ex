defmodule MilosTraining.Application.GetWorkoutDslAuthoring do
  @moduledoc """
  Returns retained Quick Text state or a canonical source generated from the
  current structured workout.
  """

  alias MilosTraining.Workouts

  def call(id) do
    case Workouts.get_workout_for_admin(id) do
      nil ->
        {:error, :not_found}

      workout ->
        source = workout.dsl_source || source_from_workout(workout)

        {:ok,
         %{
           version: workout.dsl_version || 1,
           source: source,
           document: workout.dsl_document,
           source_revision: workout.dsl_source_revision || 0,
           authoring_mode: workout.authoring_mode || "structured",
           diagnostics: workout.last_dsl_diagnostics || []
         }}
    end
  end

  defp source_from_workout(%{status: "draft", draft_data: draft_data})
       when is_map(draft_data) and map_size(draft_data) > 0,
       do: Workouts.format_dsl(draft_data)

  defp source_from_workout(workout), do: Workouts.format_dsl(workout)
end
