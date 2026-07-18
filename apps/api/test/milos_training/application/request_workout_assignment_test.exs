defmodule MilosTraining.Application.RequestWorkoutAssignmentTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.RequestWorkoutAssignment
  alias MilosTraining.{Messaging, Notifications}

  import MilosTraining.TestFixtures

  test "creates an actionable admin notification instead of a chat message" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete, nickname: "atlas_requester"})
    requested_for_iso = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    assert {:ok, %{notified_admins: 1}} =
             RequestWorkoutAssignment.call(athlete, %{
               "requested_for" => requested_for_iso,
               "note" => "Please program a strength session."
             })

    assert Messaging.list_threads_for_user(admin.id) == []

    assert [notification] = Notifications.list_for_user(admin.id)
    assert notification.type == "workout_assignment_requested"

    assert notification.payload["url"] ==
             "/admin/coaching-assignments?date=#{requested_for_iso}"
  end
end
