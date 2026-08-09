defmodule MilosTrainingWeb.AdminCoachingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Messaging, Notifications, Organizations, Repo}
  alias MilosTraining.{Execution, Workouts}
  alias MilosTraining.Notifications.Notification
  alias MilosTraining.Workers.DispatchMessageJob

  import MilosTraining.TestFixtures

  defp legacy_org_with_members!(members) do
    legacy_organization = Organizations.get_by_slug(Organizations.legacy_organization_slug())

    for {user, role} <- members do
      case Organizations.OrganizationStore.get_membership(legacy_organization.id, user.id) do
        nil ->
          {:ok, _membership} =
            Organizations.add_membership(%{
              organization_id: legacy_organization.id,
              user_id: user.id,
              role: role,
              status: :active,
              joined_at: DateTime.utc_now()
            })

        _existing ->
          :ok
      end
    end

    legacy_organization
  end

  defp set_tenant_session!(organization_id, user_id) do
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization_id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", user_id])
  end

  test "admin can send a coaching note and create a hidden chat delivery record", %{
    conn: conn
  } do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    legacy_organization = legacy_org_with_members!([{admin, :owner}, {athlete, :athlete}])
    set_tenant_session!(legacy_organization.id, admin.id)

    {:ok, thread} =
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: athlete.id
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{legacy_organization.slug}/me/threads/#{thread.id}/messages",
        %{
          body: "Keep your squat tempo controlled this week.",
          message_type: "coaching_note"
        }
      )
      |> json_response(201)

    assert response["message"]["sender_id"] == admin.id
    assert response["message"]["body"] == "Keep your squat tempo controlled this week."
    assert response["message"]["message_type"] == "coaching_note"

    assert :ok =
             DispatchMessageJob.perform(%Oban.Job{
               args: %{
                 "message_id" => response["message"]["id"],
                 "organization_id" => thread.organization_id
               }
             })

    notification =
      Repo.get_by!(Notification,
        user_id: athlete.id,
        type: :chat_message,
        dedupe_key: "chat-message:#{response["message"]["id"]}"
      )

    assert notification.payload["url"] == "/account/activity/chats?thread=#{thread.id}"
    assert Notifications.list_for_user(athlete.id) == []
    assert Messaging.count_unread_threads(athlete.id) == 1
  end

  test "admin can fetch an athlete coaching drill-down", %{conn: conn} do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete, nickname: "coaching_drill_athlete"})
    legacy_organization = legacy_org_with_members!([{admin, :owner}, {athlete, :athlete}])
    set_tenant_session!(legacy_organization.id, admin.id)
    workout = workout_fixture(admin, %{title: "Coaching Drill Workout", type: :strength})

    {:ok, tenant_context} =
      Organizations.resolve_tenant_context(admin, legacy_organization.slug)

    assert {:ok, assignment} =
             Workouts.assign_workout(tenant_context, %{
               master_workout_id: workout.id,
               scheduled_for: Date.utc_today(),
               athlete_ids: [athlete.id],
               admin_notes: "Focus on pacing."
             })

    set_tenant_session!(legacy_organization.id, athlete.id)

    assert {:ok, execution} =
             Execution.start_execution(athlete.id, %{
               organization_id: legacy_organization.id,
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

    set_tenant_session!(legacy_organization.id, admin.id)

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
      |> get("/api/org/#{legacy_organization.slug}/admin/athletes/#{athlete.id}/drill-down")
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
end
