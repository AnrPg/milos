defmodule MilosTraining.Application.GetWorkoutExecution do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Workouts

  def call(context, execution_id, actor),
    do: ExecutionStore.with_user_context(context, fn -> call(execution_id, actor) end)

  def call(execution_id, %{role: :admin}) do
    case Execution.get_execution(execution_id) do
      nil -> {:error, :not_found}
      execution -> {:ok, attach_workout_summary(execution)}
    end
  end

  def call(execution_id, user) do
    case Execution.get_execution_for_user(execution_id, user.id) do
      nil -> {:error, :not_found}
      execution -> {:ok, attach_workout_summary(execution)}
    end
  end

  defp attach_workout_summary(execution) do
    case execution.master_workout_id && Workouts.get_workout(execution.master_workout_id) do
      nil ->
        Map.merge(execution, %{
          workout_title: "Deleted workout",
          workout_type: nil,
          section_scores: attach_section_names(execution.section_scores || [], %{})
        })

      workout ->
        presented_workout =
          case execution.scale_level_slug do
            nil -> workout
            scale_slug -> Workouts.materialize_workout_for_scale(workout.id, scale_slug)
          end

        Map.merge(execution, %{
          workout_title: workout.title,
          workout_type: workout.type,
          workout: presented_workout,
          section_scores:
            attach_section_names(execution.section_scores || [], section_name_lookup(workout))
        })
    end
  end

  defp attach_section_names(section_scores, lookup) do
    Enum.map(section_scores, fn score ->
      Map.put(score, :section_name, Map.get(lookup, score[:section_id] || score["section_id"]))
    end)
  end

  defp section_name_lookup(workout) do
    workout.sections
    |> Enum.map(fn section -> {section.id, section.name} end)
    |> Map.new()
  end
end
