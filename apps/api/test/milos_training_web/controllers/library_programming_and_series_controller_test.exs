defmodule MilosTrainingWeb.LibraryProgrammingAndSeriesControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  test "admin organizes workouts in nested folders and moves a workout", %{conn: conn} do
    admin = admin_fixture(%{nickname: "folder_admin"})
    workout = workout_fixture(admin, %{title: "Folder WOD"})
    admin_conn = put_bearer_token(conn, admin)

    parent =
      admin_conn
      |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workout-folders", %{name: "2026", parent_id: nil})
      |> json_response(201)

    child =
      admin_conn
      |> recycle()
      |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workout-folders", %{name: "Strength", parent_id: parent["id"]})
      |> json_response(201)

    metadata =
      admin_conn
      |> recycle()
      |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{workout.id}/library", %{folder_id: child["id"]})
      |> json_response(200)

    assert metadata["folder_id"] == child["id"]

    folders =
      admin_conn
      |> recycle()
      |> get("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workout-folders")
      |> json_response(200)
      |> Map.fetch!("folders")

    assert Enum.any?(folders, &(&1["parent_id"] == parent["id"] and &1["name"] == "Strength"))
  end

  test "admin settings persist class creation defaults", %{conn: conn} do
    admin = admin_fixture(%{nickname: "defaults_admin"})

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/settings", %{
        scheduling: %{
          default_capacity: 18,
          default_auto_approve: true,
          default_booking_timeout_minutes: 25
        }
      })
      |> json_response(200)

    assert payload["scheduling"] == %{
             "default_capacity" => 18,
             "default_auto_approve" => true,
             "default_booking_timeout_minutes" => 25,
             "id" => payload["scheduling"]["id"],
             "organization_id" => payload["scheduling"]["organization_id"],
             "inserted_at" => payload["scheduling"]["inserted_at"],
             "updated_at" => payload["scheduling"]["updated_at"]
           }
  end

  test "admin batch creates explicit class occurrences", %{conn: conn} do
    admin = admin_fixture(%{nickname: "series_admin"})
    class_type = class_type_fixture(%{name: "Series Class"})
    admin_conn = put_bearer_token(conn, admin)
    first = Date.utc_today() |> Date.add(1)
    second = Date.add(first, 7)

    result =
      admin_conn
      |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots/series", %{
        class_type_id: class_type.id,
        name: "Weekly Series",
        duration_minutes: 60,
        timezone: "Etc/UTC",
        starts_on: Date.to_iso8601(first),
        ends_on: Date.to_iso8601(second),
        local_start_time: "09:00:00",
        weekdays: [Date.day_of_week(first)],
        excluded_dates: [],
        capacity: 14,
        auto_approve: false,
        booking_timeout_minutes: 30
      })
      |> json_response(201)

    assert result["series"]["occurrence_count"] == 2
    assert result["series"]["master_workout_id"] == nil
  end

  test "member profile schedule can copy a WOD into a folder and attach it to the booked class",
       %{conn: conn} do
    admin = admin_fixture(%{nickname: "profile_program_admin"})
    member = user_fixture(%{nickname: "profile_program_member", role: :member})
    unbooked_member = user_fixture(%{nickname: "unbooked_profile_member", role: :member})
    source = workout_fixture(admin, %{title: "Reusable Template"})
    class_type = class_type_fixture(%{name: "Profile Class"})
    admin_conn = put_bearer_token(conn, admin)
    scheduled_at = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)

    folder =
      admin_conn
      |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workout-folders", %{name: "Personalized", parent_id: nil})
      |> json_response(201)

    slot =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: source.id,
          class_type_id: class_type.id,
          name: "Profile Class",
          duration_minutes: 60,
          scheduled_at: scheduled_at,
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        })
      )
      |> json_response(201)
      |> Map.fetch!("slot")

    conn
    |> put_bearer_token(member)
    |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/bookings", Jason.encode!(%{slot_id: slot["id"]}))
    |> json_response(201)

    day = DateTime.to_date(scheduled_at) |> Date.to_iso8601()

    schedule =
      admin_conn
      |> recycle()
      |> get("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{member.id}/schedule?start_date=#{day}&end_date=#{day}")
      |> json_response(200)

    assert [%{"id" => slot_id, "kind" => "class"}] = schedule["items"]
    assert slot_id == slot["id"]

    rejected =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{unbooked_member.id}/programming",
        Jason.encode!(%{
          master_workout_id: source.id,
          folder_id: folder["id"],
          scheduled_for: day,
          slot_id: slot["id"],
          copy_source: true
        })
      )
      |> json_response(422)

    assert rejected["code"] == "slot_not_booked_by_member"
    assert MilosTraining.Scheduling.get_slot(slot["id"]).master_workout_id == source.id

    programmed =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{member.id}/programming",
        Jason.encode!(%{
          master_workout_id: source.id,
          folder_id: folder["id"],
          scheduled_for: day,
          slot_id: slot["id"],
          copy_source: true
        })
      )
      |> json_response(201)

    copied = programmed["workout"]
    assert copied["source_workout_id"] == source.id
    assert copied["folder_id"] == folder["id"]
    assert MilosTraining.Scheduling.get_slot(slot["id"]).master_workout_id == copied["id"]
  end

  test "athlete profile can save a newly-created WOD in a folder and assign that same copy",
       %{conn: conn} do
    admin = admin_fixture(%{nickname: "athlete_program_admin"})
    athlete = user_fixture(%{nickname: "profile_program_athlete", role: :athlete})
    workout = workout_fixture(admin, %{title: "Athlete-only WOD"})
    provision_programming_entitlement(athlete)
    admin_conn = put_bearer_token(conn, admin)
    day = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()

    folder =
      admin_conn
      |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workout-folders", %{name: "Athlete Plans", parent_id: nil})
      |> json_response(201)

    programmed =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{athlete.id}/programming",
        Jason.encode!(%{
          master_workout_id: workout.id,
          folder_id: folder["id"],
          scheduled_for: day,
          copy_source: false
        })
      )
      |> json_response(201)

    assert programmed["workout"]["id"] == workout.id
    assert programmed["workout"]["folder_id"] == folder["id"]

    schedule =
      admin_conn
      |> recycle()
      |> get("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{athlete.id}/schedule?start_date=#{day}&end_date=#{day}")
      |> json_response(200)

    assert [%{"kind" => "assignment", "workout" => %{"id" => workout_id}}] = schedule["items"]
    assert workout_id == workout.id
  end

  defp provision_programming_entitlement(athlete) do
    code = "profile-programming-#{System.unique_integer([:positive])}"

    {:ok, package} =
      MilosTraining.Finance.create_package(%{
        code: code,
        name: "Profile programming",
        family: "online",
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 1,
          "channels" => ["personal_programming"],
          "capabilities" => ["execute_assigned_workouts", "receive_coaching_touchpoints"],
          "allowances" => %{
            "coaching_touchpoints" => %{
              "limit" => "unlimited",
              "period" => "calendar_month"
            }
          }
        }
      })

    {:ok, membership} =
      MilosTraining.Finance.upsert_membership(athlete.id, %{
        user_type_snapshot: "athlete",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      MilosTraining.Finance.assign_package(membership.id, package.id, %{
        starts_on: Date.utc_today()
      })
  end
end
