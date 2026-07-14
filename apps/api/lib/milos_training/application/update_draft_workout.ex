defmodule MilosTraining.Application.UpdateDraftWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Identity
  alias MilosTraining.Workouts

  def call(id, params) do
    with {:ok, draft} <- Workouts.update_draft(id, params) do
      broadcast_draft_refresh(draft.id, params)
      {:ok, draft}
    end
  end

  defp broadcast_draft_refresh(draft_id, params) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

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
