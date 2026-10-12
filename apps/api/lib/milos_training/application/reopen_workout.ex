defmodule MilosTraining.Application.ReopenWorkout do
  alias MilosTraining.Application.{BroadcastUserSync, TenantStaffRecipients}
  alias MilosTraining.Workouts

  def call(context, id) do
    with {:ok, draft} <-
           Workouts.with_tenant_context(context, fn -> Workouts.reopen_workout(id) end) do
      broadcast_admin_refresh([context, draft], "workout_reopened", draft.id)
      {:ok, draft}
    end
  end

  def call(id) do
    with {:ok, draft} <- Workouts.reopen_workout(id) do
      broadcast_admin_refresh([draft], "workout_reopened", draft.id)
      {:ok, draft}
    end
  end

  defp broadcast_admin_refresh(sources, reason, draft_id) do
    admin_ids = TenantStaffRecipients.user_ids(sources)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: reason,
      payload: %{draft_id: draft_id}
    )
  end
end
