defmodule MilosTraining.Application.CreateWorkoutWithSections do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Workouts}

  def call(admin, params) do
    with {:ok, workout} <- Workouts.create_workout(admin, params) do
      admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

      BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
        reason: "workout_created",
        payload: %{workout_id: workout.id}
      )

      {:ok, workout}
    end
  end
end
