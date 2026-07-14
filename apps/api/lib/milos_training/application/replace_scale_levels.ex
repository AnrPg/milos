defmodule MilosTraining.Application.ReplaceScaleLevels do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(params) when is_list(params) do
    with {:ok, scale_levels} <- Workouts.replace_scale_levels(params) do
      admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

      BroadcastUserSync.for_users(
        admin_ids,
        ["admin_workouts"],
        reason: "scale_levels_updated",
        payload: %{scale_level_count: length(scale_levels)}
      )

      {:ok, scale_levels}
    end
  end
end
