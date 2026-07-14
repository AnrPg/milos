defmodule MilosTraining.Application.ReopenWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(id) do
    with {:ok, draft} <- Workouts.reopen_workout(id) do
      broadcast_admin_refresh("workout_reopened", draft.id)
      {:ok, draft}
    end
  end

  defp broadcast_admin_refresh(reason, draft_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: reason,
      payload: %{draft_id: draft_id}
    )
  end
end
