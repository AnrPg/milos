defmodule MilosTraining.Application.ListWorkoutExecutions do
  alias MilosTraining.Execution
  alias MilosTraining.Workouts

  def call(user_id) do
    executions =
      user_id
      |> Execution.list_executions_for_user()
      |> Enum.map(&attach_workout_summary/1)

    {:ok, executions}
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
        Map.merge(execution, %{
          workout_title: workout.title,
          workout_type: workout.type,
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
