defmodule Palee.Application.UpdateDraftWorkout do
  alias Palee.Application.{BroadcastUserSync, TenantStaffRecipients}
  alias Palee.Workouts

  def call(id, params) do
    with {:ok, draft} <- Workouts.update_draft(id, params) do
      broadcast_draft_refresh([draft], draft.id, params)
      {:ok, draft}
    end
  end

  def call(context, id, params) do
    with {:ok, draft} <- Palee.Workouts.WorkoutStore.update_draft(context, id, params) do
      broadcast_draft_refresh([context, draft], draft.id, params)
      {:ok, draft}
    end
  end

  defp broadcast_draft_refresh(sources, draft_id, params) do
    admin_ids = TenantStaffRecipients.user_ids(sources)

    BroadcastUserSync.for_users(
      admin_ids,
      ["admin_workouts"],
      reason: "draft_updated",
      payload: %{
        draft_id: draft_id,
        editor_session_id:
          Map.get(params, :editor_session_id) || Map.get(params, "editor_session_id")
      }
    )
  end
end
