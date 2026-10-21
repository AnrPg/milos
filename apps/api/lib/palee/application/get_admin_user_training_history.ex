defmodule Palee.Application.GetAdminUserTrainingHistory do
  @moduledoc """
  Staff dossier training tab. Executions are the member's journal entries:
  they are read only while the member is active here (ADR-162 §7); the
  gym's own assignments stay visible.
  """

  alias Palee.Application.{
    GetCoachingAthleteDrillDown,
    ListWorkoutExecutions,
    StaffJournalAccess
  }

  alias Palee.Identity

  def call(context, user_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, executions} <- executions(context, user_id) do
      history = Enum.map(executions, &execution_summary/1)

      {:ok,
       %{
         user_id: user_id,
         executions: history,
         scores: Enum.flat_map(history, &scores_for_execution/1),
         class_participation: Enum.filter(history, &(&1.source == "class_booking")),
         assigned_workouts: assigned_workouts(context, user),
         summary: %{
           execution_count: length(history),
           completed_count: Enum.count(history, &(&1.status == "completed")),
           scored_section_count: Enum.reduce(history, 0, &(length(&1.section_scores) + &2))
         }
       }}
    end
  end

  defp executions(context, user_id) do
    if StaffJournalAccess.readable?(context, user_id),
      do: ListWorkoutExecutions.call(context, user_id),
      else: {:ok, []}
  end

  # Assignments are tenant data: read them in the dossier's tenant (ADR-133).
  defp assigned_workouts(context, %{role: :athlete, id: id}) do
    case GetCoachingAthleteDrillDown.call(context, id, %{}) do
      {:ok, %{drill_down: drill_down}} -> drill_down.assigned_workouts
      _ -> []
    end
  end

  defp assigned_workouts(_context, _user), do: []

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
      section_scores: execution.section_scores || [],
      duration_adjustments: Map.get(execution, :duration_adjustments) || %{}
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
