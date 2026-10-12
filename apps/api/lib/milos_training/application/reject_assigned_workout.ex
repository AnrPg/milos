defmodule MilosTraining.Application.RejectAssignedWorkout do
  alias MilosTraining.Application.{BroadcastUserSync, TenantStaffRecipients, TrackAnalyticsEvent}
  alias MilosTraining.{Identity, Notifications, Workouts}

  def call(context, assignment_id, athlete_id) do
    Workouts.with_tenant_context(context, fn ->
      do_call(context, assignment_id, athlete_id)
    end)
  end

  def call(assignment_id, athlete_id), do: do_call(nil, assignment_id, athlete_id)

  defp do_call(context, assignment_id, athlete_id) do
    with {:ok, assignment} <- Workouts.reject_assignment_for_athlete(assignment_id, athlete_id) do
      athlete = Identity.find_by_id(athlete_id)
      dispatch_rejected_notification(context, assignment, athlete)
      broadcast_assignment_refresh(context, assignment)

      TrackAnalyticsEvent.call("workout_assignment_rejected", context, assignment, %{
        user_id: athlete_id
      })

      {:ok, assignment}
    end
  end

  defp dispatch_rejected_notification(context, assignment, athlete) do
    workout_title =
      assignment
      |> Map.get(:workout, %{})
      |> Map.get(:title, "a workout")

    athlete_nickname = (athlete && athlete.nickname) || "An athlete"

    # Staff recipients are resolved from the owning organization; without it
    # the rejection reached nobody.
    Notifications.dispatch_event(:workout_rejected, %{
      organization_id:
        (context && Map.get(context, :organization_id)) || Map.get(assignment, :organization_id),
      assigned_workout_id: assignment.id,
      workout_title: workout_title,
      athlete_nickname: athlete_nickname,
      scheduled_for: assignment.scheduled_for
    })
  end

  defp broadcast_assignment_refresh(context, assignment) do
    admin_ids = TenantStaffRecipients.user_ids([context, assignment])

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_rejected",
      payload: %{assignment_id: assignment.id}
    )
  end
end
