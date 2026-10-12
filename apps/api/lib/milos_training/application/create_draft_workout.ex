defmodule MilosTraining.Application.CreateDraftWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(admin) do
    with {:ok, draft} <- Workouts.create_draft(admin) do
      broadcast_admin_refresh("draft_created", draft.id)
      {:ok, draft}
    end
  end

  def call(context, admin), do: call(context, admin, nil)

  @doc "Creates an empty draft, filed in `folder_id` when given (`nil` = library root)."
  def call(context, admin, folder_id) do
    with :ok <- validate_folder(context, folder_id),
         {:ok, draft} <- Workouts.create_draft(context, admin),
         {:ok, draft} <- file_draft(context, draft, folder_id) do
      broadcast_admin_refresh("draft_created", draft.id)
      {:ok, draft}
    end
  end

  defp validate_folder(_context, nil), do: :ok

  defp validate_folder(context, folder_id) do
    if Enum.any?(Workouts.list_folders(context), &(&1.id == folder_id)),
      do: :ok,
      else: {:error, :folder_parent_not_found}
  end

  defp file_draft(_context, draft, nil), do: {:ok, draft}

  defp file_draft(context, draft, folder_id) do
    with {:ok, _metadata} <-
           Workouts.update_library_metadata(context, draft.id, %{folder_id: folder_id}) do
      {:ok, Map.put(draft, :folder_id, folder_id)}
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
