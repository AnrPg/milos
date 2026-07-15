defmodule MilosTrainingWeb.AdminCoachingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Messaging, Notifications}
  alias MilosTraining.{Execution, Workouts}

  import MilosTraining.TestFixtures

  test "admin can send a coaching note via messaging and trigger an athlete notification", %{
    conn: conn
  } do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    {:ok, thread} =
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: athlete.id
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> post("/api/threads/#{thread.id}/messages", %{
        body: "Keep your squat tempo controlled this week.",
        message_type: "coaching_note"
      })
      |> json_response(201)

    assert response["message"]["sender_id"] == admin.id
    assert response["message"]["body"] == "Keep your squat tempo controlled this week."
    assert response["message"]["message_type"] == "coaching_note"

    notifications = wait_for_notifications(athlete.id)

    assert Enum.any?(notifications, fn notification ->
             notification.type in [:chat_message, "chat_message"] and
               notification.payload["url"] == "/account/activity/chats?thread=#{thread.id}"
           end)
  end

  test "admin can fetch an athlete coaching drill-down", %{conn: conn} do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete, nickname: "coaching_drill_athlete"})
    workout = workout_fixture(admin, %{title: "Coaching Drill Workout", type: :strength})

    assert {:ok, assignment} =
             Workouts.assign_workout(%{
               master_workout_id: workout.id,
               scheduled_for: Date.utc_today(),
               athlete_ids: [athlete.id],
               admin_notes: "Focus on pacing."
             })

    assert {:ok, execution} =
             Execution.start_execution(athlete.id, %{
               master_workout_id: workout.id,
               source: :assigned,
               source_reference_id: assignment.id,
               status: :active,
               started_at_utc: DateTime.utc_now(),
               started_at_tz: "UTC"
             })

    section = hd(workout.sections)

    assert {:ok, _completed} =
             Execution.complete_execution(execution.id, athlete.id, %{
               completed_at_utc: DateTime.utc_now(),
               completed_at_tz: "UTC",
               status: :completed,
               section_scores: [
                 %{section_id: section.id, value: 120, unit: "kg"}
               ],
               exercise_notes: [
                 %{
                   id: Ecto.UUID.generate(),
                   exercise_id: hd(section.exercises).id,
                   selected_text: "tempo",
                   note_text: "Knee felt good",
                   tags: ["form"],
                   inserted_at: DateTime.utc_now()
                 }
               ]
             })

    {:ok, thread} =
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: athlete.id
      })

    {:ok, _msg} =
      Messaging.send_message(%{
        thread_id: thread.id,
        sender_id: admin.id,
        body: "Keep strength work steady.",
        message_type: :coaching_note
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> get("/api/admin/athletes/#{athlete.id}/drill-down")
      |> json_response(200)

    assert response["drill_down"]["identity"]["nickname"] == "coaching_drill_athlete"
    assert response["drill_down"]["recent_activity"]["state"] == "active"

    assert [%{"status" => "completed"} = assignment_response] =
             response["drill_down"]["assigned_workouts"]

    assert assignment_response["id"] == assignment.id

    assert [%{"workout_type" => "strength"}] = response["drill_down"]["score_trends"]

    assert Enum.any?(response["drill_down"]["notes_context"], fn note ->
             note["type"] == "admin_note" and note["body"] == "Keep strength work steady."
           end)

    action_keys = Enum.map(response["drill_down"]["actions"], & &1["key"])
    assert "write_note" in action_keys
  end

  defp wait_for_notifications(user_id, attempts \\ 10)

  defp wait_for_notifications(user_id, attempts) when attempts > 0 do
    notifications = Notifications.list_for_user(user_id)

    if notifications == [] do
      Process.sleep(50)
      wait_for_notifications(user_id, attempts - 1)
    else
      notifications
    end
  end

  defp wait_for_notifications(user_id, 0), do: Notifications.list_for_user(user_id)
end
