defmodule MilosTraining.Application.RejectAssignedWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Notifications, Workouts}

  def call(assignment_id, athlete_id) do
    with {:ok, assignment} <- Workouts.reject_assignment_for_athlete(assignment_id, athlete_id) do
      athlete = Identity.find_by_id(athlete_id)
      dispatch_rejected_notification(assignment, athlete)
      broadcast_assignment_refresh(assignment)
      {:ok, assignment}
    end
  end

  defp dispatch_rejected_notification(assignment, athlete) do
    workout_title =
      assignment
      |> Map.get(:workout, %{})
      |> Map.get(:title, "a workout")

    athlete_nickname = (athlete && athlete.nickname) || "An athlete"

    Notifications.dispatch_event(:workout_rejected, %{
      assigned_workout_id: assignment.id,
      workout_title: workout_title,
      athlete_nickname: athlete_nickname,
      scheduled_for: assignment.scheduled_for
    })
  end

  defp broadcast_assignment_refresh(assignment) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_rejected",
      payload: %{assignment_id: assignment.id}
    )
  end
end
