defmodule MilosTraining.Application.RescheduleAssignedWorkout do
  require Logger

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Notifications, Workouts}

  def call(assignment_id, athlete_id, new_date_str) do
    with {:ok, new_date} <- parse_date(new_date_str),
         :ok <- guard_future_date(new_date),
         assignment when not is_nil(assignment) <- Workouts.get_assigned_workout(assignment_id),
         :ok <- verify_athlete_access(assignment, athlete_id),
         {:ok, updated} <- Workouts.update_assignment_date(assignment_id, assignment.scheduled_for, new_date) do
      notify_admins_workout_moved(assignment, updated, athlete_id)
      broadcast_assignment_refresh(assignment, athlete_id)
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, :past_date} = e -> e
      {:error, :forbidden} = e -> e
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :bad_request}
    end
  end

  defp guard_future_date(date) do
    if Date.compare(date, Date.utc_today()) == :lt do
      {:error, :past_date}
    else
      :ok
    end
  end

  defp verify_athlete_access(assignment, athlete_id) do
    athlete_ids = Map.get(assignment, :athlete_ids, []) || []
    if athlete_id in athlete_ids, do: :ok, else: {:error, :forbidden}
  end

  defp notify_admins_workout_moved(assignment, updated, athlete_id) do
    athlete = Identity.find_by_id(athlete_id)
    athlete_nickname = (athlete && athlete.nickname) || "An athlete"
    workout_title = updated |> Map.get(:workout, %{}) |> Map.get(:title, "a workout")
    from_date = assignment.scheduled_for
    to_date = Map.get(updated, :scheduled_for, "")

    Notifications.dispatch_event(:workout_moved, %{
      assigned_workout_id: assignment.id,
      athlete_nickname: athlete_nickname,
      workout_title: workout_title,
      from_date: from_date,
      to_date: to_date
    })
  end

  defp broadcast_assignment_refresh(assignment, athlete_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      [athlete_id | admin_ids],
      ["assigned_workouts"],
      reason: "assignment_rescheduled",
      payload: %{assignment_id: assignment.id}
    )
  end
end
