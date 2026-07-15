defmodule MilosTrainingWeb.ScheduleControllerTest do
  use MilosTrainingWeb.ConnCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Notifications
  alias Oban.Testing

  import MilosTraining.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    :ok
  end

  test "member can list schedule, book a slot, and admin can approve it", %{conn: conn} do
    Testing.with_testing_mode(:manual, fn ->
      admin = admin_fixture(%{nickname: "sched_admin"})
      member = user_fixture(%{nickname: "sched_member"})
      workout = workout_fixture(admin, %{title: "Morning Burner"})
      class_type = class_type_fixture(%{name: "Morning Class"})

      admin_conn = put_bearer_token(conn, admin)

      create_response =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/admin/schedule/slots",
          Jason.encode!(%{
            master_workout_id: workout.id,
            class_type_id: class_type.id,
            scheduled_at:
              DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second),
            capacity: 12,
            auto_approve: false,
            booking_timeout_minutes: 45
          })
        )

      slot = json_response(create_response, 201)["slot"]

      member_conn = put_bearer_token(conn, member)

      index_response =
        get(
          member_conn,
          "/api/schedule?start_date=#{Date.utc_today()}&days=7&class_type_ids[]=#{class_type.id}"
        )

      payload = json_response(index_response, 200)
      assert Enum.any?(payload["slots"], &(&1["id"] == slot["id"]))

      booking_response =
        member_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/bookings", Jason.encode!(%{slot_id: slot["id"]}))

      booking = json_response(booking_response, 201)["booking"]
      assert booking["status"] == "pending"

      approve_response =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> patch(
          "/api/admin/bookings/#{booking["id"]}/approve",
          Jason.encode!(%{admin_message: "See you there"})
        )

      approved = json_response(approve_response, 200)["booking"]
      assert approved["status"] == "approved"

      Oban.drain_queue(queue: :notifications, with_safety: false)

      member_notifications = wait_for_notifications(member.id)
      assert Enum.any?(member_notifications, &(&1.type == "booking_approved"))
    end)
  end

  test "admin can delete an empty slot", %{conn: conn} do
    admin = admin_fixture(%{nickname: "slot_admin"})
    workout = workout_fixture(admin)
    class_type = class_type_fixture(%{name: "Open Gym"})
    admin_conn = put_bearer_token(conn, admin)

    create_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: workout.id,
          class_type_id: class_type.id,
          scheduled_at:
            DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second),
          capacity: 8,
          auto_approve: false,
          booking_timeout_minutes: 30
        })
      )

    slot = json_response(create_response, 201)["slot"]

    delete_conn = delete(admin_conn |> recycle(), "/api/admin/schedule/slots/#{slot["id"]}")
    assert response(delete_conn, 204)
  end

  test "schedule preview survives republished workouts with scale overrides", %{conn: conn} do
    admin = admin_fixture(%{nickname: "edited_schedule_admin"})

    {:ok, _levels} =
      MilosTraining.Workouts.replace_scale_levels([
        %{slug: "scaled", label: "Scaled", sort_order: 1},
        %{slug: "rx", label: "Rx", sort_order: 2}
      ])

    workout =
      workout_fixture(admin, %{
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Power Cleans",
                order: 1,
                sets: 4,
                prescription_value: 6,
                prescription_unit: "reps",
                variations: [
                  %{scale_level_slug: "rx", sets: 6, exercise_name_override: "Squat Cleans"}
                ]
              }
            ]
          }
        ]
      })

    admin_conn = put_bearer_token(conn, admin)
    class_type = class_type_fixture(%{name: "Republish Class"})

    reopen_response = post(admin_conn |> recycle(), "/api/admin/workouts/#{workout.id}/reopen")
    assert json_response(reopen_response, 200)["draft"]["status"] == "published"

    member = user_fixture(%{nickname: "live_during_edit_member", role: :member})
    member_conn = put_bearer_token(conn, member)
    still_live = get(member_conn |> recycle(), "/api/workouts/#{workout.id}")
    assert json_response(still_live, 200)["workout"]["id"] == workout.id

    publish_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/api/admin/workouts/#{workout.id}/publish", Jason.encode!(%{}))

    assert json_response(publish_response, 200)["workout"]["status"] == "published"

    create_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: workout.id,
          class_type_id: class_type.id,
          scheduled_at:
            DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second),
          capacity: 12,
          auto_approve: false,
          booking_timeout_minutes: 45
        })
      )

    slot = json_response(create_response, 201)["slot"]

    response =
      get(
        admin_conn |> recycle(),
        "/api/schedule?start_date=#{Date.utc_today()}&days=7&class_type_ids[]=#{class_type.id}"
      )

    payload = json_response(response, 200)
    schedule_slot = Enum.find(payload["slots"], &(&1["id"] == slot["id"]))

    assert schedule_slot["workout"]["sections"]
           |> hd()
           |> Map.fetch!("exercises")
           |> hd()
           |> Map.fetch!("variations")
           |> hd()
           |> Map.fetch!("exercise_name_override") == "Squat Cleans"
  end

  defp wait_for_notifications(user_id, attempts \\ 10)

  defp wait_for_notifications(user_id, attempts) when attempts > 0 do
    notifications = Notifications.list_for_user(user_id)

    if notifications == [] do
      Process.sleep(20)
      wait_for_notifications(user_id, attempts - 1)
    else
      notifications
    end
  end

  defp wait_for_notifications(user_id, 0), do: Notifications.list_for_user(user_id)
end
