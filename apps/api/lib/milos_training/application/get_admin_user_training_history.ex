defmodule MilosTraining.Application.GetAdminUserTrainingHistory do
  @moduledoc false

  alias MilosTraining.Application.{GetCoachingAthleteDrillDown, ListWorkoutExecutions}
  alias MilosTraining.Identity

  def call(user_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, executions} <- ListWorkoutExecutions.call(user_id) do
      history = Enum.map(executions, &execution_summary/1)

      {:ok,
       %{
         user_id: user_id,
         executions: history,
         scores: Enum.flat_map(history, &scores_for_execution/1),
         class_participation: Enum.filter(history, &(&1.source == "class_booking")),
         assigned_workouts: assigned_workouts(user),
         summary: %{
           execution_count: length(history),
           completed_count: Enum.count(history, &(&1.status == "completed")),
           scored_section_count: Enum.reduce(history, 0, &(length(&1.section_scores) + &2))
         }
       }}
    end
  end

  defp assigned_workouts(%{role: :athlete, id: id}) do
    case GetCoachingAthleteDrillDown.call(id) do
      {:ok, %{drill_down: drill_down}} -> drill_down.assigned_workouts
      _ -> []
    end
  end

  defp assigned_workouts(_user), do: []

  defp execution_summary(execution) do
    %{
      id: execution.id,
      master_workout_id: execution.master_workout_id,
      workout_title: execution.workout_title,
      workout_type: string(execution.workout_type),
      source: string(execution.source),
      status: string(execution.status),
      scale_level_slug: execution.scale_level_slug,
      started_at_utc: execution.started_at_utc,
      completed_at_utc: execution.completed_at_utc,
      total_elapsed_ms: execution.total_elapsed_ms,
      section_scores: execution.section_scores || []
    }
  end

  defp scores_for_execution(execution) do
    Enum.map(execution.section_scores, fn score ->
      %{
        execution_id: execution.id,
        workout_title: execution.workout_title,
        completed_at_utc: execution.completed_at_utc,
        section_id: field(score, :section_id),
        section_name: field(score, :section_name),
        value: field(score, :value),
        unit: field(score, :unit)
      }
    end)
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp string(nil), do: nil
  defp string(value), do: to_string(value)
end
