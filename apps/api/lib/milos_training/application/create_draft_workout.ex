defmodule MilosTraining.Application.CreateDraftWorkout do
  alias MilosTraining.Application.{BroadcastUserSync, TenantStaffRecipients, TrackAnalyticsEvent}
  alias MilosTraining.Workouts

  def call(admin) do
    with {:ok, draft} <- Workouts.create_draft(admin) do
      broadcast_admin_refresh([draft], "draft_created", draft.id)
      TrackAnalyticsEvent.call("workout_created", nil, draft, %{user_id: admin.id})
      {:ok, draft}
    end
  end

  def call(context, admin) do
    with {:ok, draft} <- Workouts.create_draft(context, admin) do
      broadcast_admin_refresh([context, draft], "draft_created", draft.id)
      TrackAnalyticsEvent.call("workout_created", context, draft)
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
