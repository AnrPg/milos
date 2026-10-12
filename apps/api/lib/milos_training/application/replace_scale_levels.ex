defmodule MilosTraining.Application.ReplaceScaleLevels do
  alias MilosTraining.Application.{BroadcastUserSync, TenantStaffRecipients}
  alias MilosTraining.Workouts

  def call(context, params) when is_list(params) do
    with {:ok, scale_levels} <- Workouts.replace_scale_levels(params) do
      context
      |> TenantStaffRecipients.user_ids()
      |> BroadcastUserSync.for_users(
        ["admin_workouts"],
        reason: "scale_levels_updated",
        payload: %{scale_level_count: length(scale_levels)}
      )

      {:ok, scale_levels}
    end
  end
end
