defmodule MilosTraining.Application.GetWorkoutVault do
  @moduledoc """
  A client's vault (ADR-098): every workout they completed, newest first, each
  with its dated entries. Entries link to that day's performance, and any entry
  can be done again as a new execution with source `repeat`.
  """

  alias MilosTraining.Application.ListWorkoutExecutions
  alias MilosTraining.Execution.ExecutionStore

  def call(context, user_id),
    do: ExecutionStore.with_user_context(context, fn -> call(user_id) end)

  def call(user_id) do
    {:ok, executions} = ListWorkoutExecutions.call(user_id)

    workouts =
      executions
      |> Enum.filter(&(&1.status == "completed" and is_binary(&1.master_workout_id)))
      |> Enum.group_by(& &1.master_workout_id)
      |> Enum.map(fn {workout_id, entries} ->
        entries = Enum.sort_by(entries, & &1.completed_at_utc, {:desc, DateTime})
        latest = hd(entries)

        %{
          master_workout_id: workout_id,
          workout_title: latest.workout_title,
          workout_type: latest.workout_type,
          completed_count: length(entries),
          last_completed_at: latest.completed_at_utc,
          entries: Enum.map(entries, &entry/1)
        }
      end)
      |> Enum.sort_by(& &1.last_completed_at, {:desc, DateTime})

    {:ok, workouts}
  end

  defp entry(execution) do
    %{
      id: execution.id,
      started_at_utc: execution.started_at_utc,
      completed_at_utc: execution.completed_at_utc,
      completed_at_tz: execution.completed_at_tz,
      scale_level_slug: execution.scale_level_slug,
      source: execution.source,
      total_elapsed_ms: execution.total_elapsed_ms
    }
  end
end
