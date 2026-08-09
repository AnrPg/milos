defmodule MilosTrainingWeb.ScheduleControllerTest do
  use MilosTrainingWeb.ConnCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Notifications, Organizations, Repo}
  alias Oban.Testing

  import MilosTraining.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    # Fixtures like `workout_fixture/2` create records through the legacy,
    # session-scoped write path (no explicit tenant context argument), which
    # resolves the target organization from the `app.organization_id` GUC.
    # Set it deterministically instead of depending on an earlier HTTP
    # request in the same shared sandbox connection having already set it.
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    :ok
  end

  test "member can list schedule, book a slot, and admin can approve it", %{conn: conn} do
    Testing.with_testing_mode(:manual, fn ->
      admin = admin_fixture(%{nickname: "sched_admin"})
      member = user_fixture(%{nickname: "sched_member"})
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member)
      workout = workout_fixture(admin, %{title: "Morning Burner"})
      class_type = class_type_fixture(%{name: "Morning Class"})

      admin_conn = put_bearer_token(conn, admin)

      create_response =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots",
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
          "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/schedule?start_date=#{Date.utc_today()}&days=7&class_type_ids[]=#{class_type.id}"
        )

      payload = json_response(index_response, 200)
      assert Enum.any?(payload["slots"], &(&1["id"] == slot["id"]))

      booking_response =
        member_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/bookings",
          Jason.encode!(%{slot_id: slot["id"]})
        )

      booking = json_response(booking_response, 201)["booking"]
      assert booking["status"] == "pending"

      approve_response =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> patch(
          "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/bookings/#{booking["id"]}/approve",
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
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    workout = workout_fixture(admin)
    class_type = class_type_fixture(%{name: "Open Gym"})
    admin_conn = put_bearer_token(conn, admin)

    create_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots",
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

    delete_conn =
      delete(
        admin_conn |> recycle(),
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots/#{slot["id"]}"
      )

    assert response(delete_conn, 204)
  end

  test "admin creates a recurring series with exclusions and overlapping classes", %{conn: conn} do
    admin = admin_fixture(%{nickname: "series_admin"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    workout = workout_fixture(admin, %{title: "Beginner CrossFit"})
    class_type = class_type_fixture(%{name: "CrossFit"})
    admin_conn = put_bearer_token(conn, admin)
    starts_on = Date.add(Date.utc_today(), 1)
    excluded_on = Date.add(starts_on, 7)
    ends_on = Date.add(starts_on, 14)
    weekday = Date.day_of_week(starts_on)

    series_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots/series",
        Jason.encode!(%{
          master_workout_id: workout.id,
          class_type_id: class_type.id,
          name: "CrossFit beginners",
          duration_minutes: 75,
          timezone: "Etc/UTC",
          starts_on: starts_on,
          ends_on: ends_on,
          local_start_time: "17:00:00",
          weekdays: [weekday],
          excluded_dates: [excluded_on],
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        })
      )

    assert %{
             "series" => %{
               "occurrence_count" => 2,
               "master_workout_id" => workout_id
             }
           } = json_response(series_response, 201)

    assert workout_id == workout.id

    first_start = DateTime.new!(starts_on, ~T[17:00:00], "Etc/UTC")

    overlap_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: workout.id,
          class_type_id: class_type.id,
          name: "Parallel strength",
          duration_minutes: 45,
          scheduled_at: first_start,
          capacity: 6,
          auto_approve: false,
          booking_timeout_minutes: 30
        })
      )

    assert %{"slot" => %{"name" => "Parallel strength"}} = json_response(overlap_response, 201)

    schedule =
      get(
        admin_conn |> recycle(),
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/schedule?start_at=#{URI.encode_www_form(DateTime.to_iso8601(first_start))}&end_at=#{URI.encode_www_form(DateTime.to_iso8601(DateTime.add(first_start, 16 * 86_400, :second)))}&days=30"
      )
      |> json_response(200)

    series_slots = Enum.filter(schedule["slots"], &(&1["name"] == "CrossFit beginners"))
    assert Enum.map(series_slots, & &1["duration_minutes"]) == [75, 75]

    assert length(
             Enum.filter(
               schedule["slots"],
               &(&1["scheduled_at"] == DateTime.to_iso8601(first_start))
             )
           ) == 2
  end

  test "schedule preview survives republished workouts with scale overrides", %{conn: conn} do
    admin = admin_fixture(%{nickname: "edited_schedule_admin"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

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

    reopen_response =
      post(
        admin_conn |> recycle(),
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{workout.id}/reopen"
      )

    reopened_draft = json_response(reopen_response, 200)["draft"]
    assert reopened_draft["status"] == "published"

    member = user_fixture(%{nickname: "live_during_edit_member", role: :member})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member)
    member_conn = put_bearer_token(conn, member)

    still_live =
      get(
        member_conn |> recycle(),
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/workouts/#{workout.id}"
      )

    assert json_response(still_live, 200)["workout"]["id"] == workout.id

    admin_draft =
      get(
        admin_conn |> recycle(),
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{workout.id}"
      )
      |> json_response(200)

    publish_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{workout.id}/publish",
        Jason.encode!(%{
          expected_source_revision: admin_draft["workout"]["dsl_source_revision"]
        })
      )

    assert json_response(publish_response, 200)["workout"]["status"] == "published"

    create_response =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots",
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
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/schedule?start_date=#{Date.utc_today()}&days=7&class_type_ids[]=#{class_type.id}"
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
