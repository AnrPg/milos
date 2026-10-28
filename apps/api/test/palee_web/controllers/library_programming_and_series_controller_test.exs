defmodule PaleeWeb.LibraryProgrammingAndSeriesControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Repo}
  alias Palee.Application.SuggestWorkoutIcon

  test "admin organizes workouts in nested folders and moves a workout", %{conn: conn} do
    admin = admin_fixture(%{nickname: "folder_admin"})
    %{organization: organization, context: context} = tenant_fixture(admin, "Folder Gym")
    workout = tenant_workout_fixture(admin, context, %{title: "Folder WOD"})
    admin_conn = put_bearer_token(conn, admin)

    parent =
      admin_conn
      |> post(
        "/api/org/#{organization.slug}/admin/workout-folders",
        %{name: "2026", parent_id: nil}
      )
      |> json_response(201)

    child =
      admin_conn
      |> recycle()
      |> post(
        "/api/org/#{organization.slug}/admin/workout-folders",
        %{name: "Strength", parent_id: parent["id"]}
      )
      |> json_response(201)

    metadata =
      admin_conn
      |> recycle()
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{workout.id}/library",
        %{folder_id: child["id"]}
      )
      |> json_response(200)

    assert metadata["folder_id"] == child["id"]

    folders =
      admin_conn
      |> recycle()
      |> get("/api/org/#{organization.slug}/admin/workout-folders")
      |> json_response(200)
      |> Map.fetch!("folders")

    assert Enum.any?(folders, &(&1["parent_id"] == parent["id"] and &1["name"] == "Strength"))
  end

  test "admin settings persist class creation defaults", %{conn: conn} do
    admin = admin_fixture(%{nickname: "defaults_admin"})
    %{organization: organization} = tenant_fixture(admin, "Defaults Gym")

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/settings",
        %{
          scheduling: %{
            default_capacity: 18,
            default_auto_approve: true,
            default_booking_timeout_minutes: 25
          }
        }
      )
      |> json_response(200)

    assert payload["scheduling"] == %{
             "default_capacity" => 18,
             "default_auto_approve" => true,
             "default_booking_timeout_minutes" => 25,
             "default_booking_window_days" => nil,
             "default_cancellation_cutoff_minutes" => nil,
             "id" => payload["scheduling"]["id"],
             "organization_id" => payload["scheduling"]["organization_id"],
             "inserted_at" => payload["scheduling"]["inserted_at"],
             "updated_at" => payload["scheduling"]["updated_at"]
           }
  end

  test "admin batch creates explicit class occurrences", %{conn: conn} do
    admin = admin_fixture(%{nickname: "series_admin"})
    %{organization: organization, context: context} = tenant_fixture(admin, "Series Gym")
    class_type = class_type_fixture(%{name: "Series Class", tenant_context: context})
    workout = tenant_workout_fixture(admin, context, %{title: "Series WOD"})
    admin_conn = put_bearer_token(conn, admin)
    first = Date.utc_today() |> Date.add(1)
    second = Date.add(first, 7)

    result =
      admin_conn
      |> post(
        "/api/org/#{organization.slug}/admin/schedule/slots/series",
        %{
          class_type_id: class_type.id,
          master_workout_id: workout.id,
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
        }
      )
      |> json_response(201)

    assert result["series"]["occurrence_count"] == 2
    assert result["series"]["master_workout_id"] == workout.id
  end

  test "member profile schedule can copy a WOD into a folder and attach it to the booked class",
       %{conn: conn} do
    admin = admin_fixture(%{nickname: "profile_program_admin"})
    %{organization: organization, context: context} = tenant_fixture(admin, "Profile Program Gym")
    member = user_fixture(%{nickname: "profile_program_member", role: :member})
    unbooked_member = user_fixture(%{nickname: "unbooked_profile_member", role: :member})
    add_membership(organization, member, :member)
    add_membership(organization, unbooked_member, :member)
    source = tenant_workout_fixture(admin, context, %{title: "Reusable Template"})
    class_type = class_type_fixture(%{name: "Profile Class", tenant_context: context})
    admin_conn = put_bearer_token(conn, admin)
    scheduled_at = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)

    folder =
      admin_conn
      |> post(
        "/api/org/#{organization.slug}/admin/workout-folders",
        %{name: "Personalized", parent_id: nil}
      )
      |> json_response(201)

    slot =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/schedule/slots",
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
    |> post(
      "/api/org/#{organization.slug}/bookings",
      Jason.encode!(%{slot_id: slot["id"]})
    )
    |> json_response(201)

    day = DateTime.to_date(scheduled_at) |> Date.to_iso8601()

    schedule =
      admin_conn
      |> recycle()
      |> get(
        "/api/org/#{organization.slug}/admin/users/#{member.id}/schedule?start_date=#{day}&end_date=#{day}"
      )
      |> json_response(200)

    assert [%{"id" => slot_id, "kind" => "class"}] = schedule["items"]
    assert slot_id == slot["id"]

    rejected =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/users/#{unbooked_member.id}/programming",
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

    # Creating a class files nothing; it keeps pointing at the library template.
    assert slot["master_workout_id"] == source.id
    assert Palee.Scheduling.get_slot(context, slot["id"]).master_workout_id == source.id

    programmed =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/users/#{member.id}/programming",
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

    assert Palee.Scheduling.get_slot(context, slot["id"]).master_workout_id ==
             copied["id"]
  end

  test "member profile can move a member from a booked class into another class",
       %{conn: conn} do
    admin = admin_fixture(%{nickname: "placement_admin"})
    %{organization: organization, context: context} = tenant_fixture(admin, "Placement Gym")
    member = user_fixture(%{nickname: "placement_member", role: :member})
    athlete = user_fixture(%{nickname: "placement_athlete", role: :athlete})
    add_membership(organization, member, :member)
    add_membership(organization, athlete, :athlete)
    workout = tenant_workout_fixture(admin, context, %{title: "Placement WOD"})
    class_type = class_type_fixture(%{name: "Placement Class", tenant_context: context})
    admin_conn = put_bearer_token(conn, admin)
    scheduled_at = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)

    create_slot = fn name, at, auto_approve ->
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: workout.id,
          class_type_id: class_type.id,
          name: name,
          duration_minutes: 60,
          scheduled_at: at,
          capacity: 10,
          auto_approve: auto_approve,
          booking_timeout_minutes: 30
        })
      )
      |> json_response(201)
      |> Map.fetch!("slot")
    end

    morning = create_slot.("Morning Class", scheduled_at, true)
    evening = create_slot.("Evening Class", DateTime.add(scheduled_at, 3_600), false)

    booking =
      conn
      |> put_bearer_token(member)
      |> post(
        "/api/org/#{organization.slug}/bookings",
        Jason.encode!(%{slot_id: morning["id"]})
      )
      |> json_response(201)
      |> Map.fetch!("booking")

    placement =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/users/#{member.id}/class-placement",
        Jason.encode!(%{slot_id: evening["id"], from_booking_id: booking["id"]})
      )
      |> json_response(201)

    assert placement["booking"]["status"] == "approved"
    assert placement["booking"]["scheduled_class_id"] == evening["id"]
    assert placement["previous_booking_id"] == booking["id"]

    day = DateTime.to_date(scheduled_at) |> Date.to_iso8601()
    next_day = DateTime.to_date(scheduled_at) |> Date.add(1) |> Date.to_iso8601()

    schedule =
      admin_conn
      |> recycle()
      |> get(
        "/api/org/#{organization.slug}/admin/users/#{member.id}/schedule?start_date=#{day}&end_date=#{next_day}"
      )
      |> json_response(200)

    assert [%{"id" => slot_id}] = schedule["items"]
    assert slot_id == evening["id"]

    rejected =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/users/#{athlete.id}/class-placement",
        Jason.encode!(%{slot_id: morning["id"]})
      )
      |> json_response(422)

    assert rejected["code"] == "class_placement_requires_member"
  end

  test "athlete profile can save a newly-created WOD in a folder and assign that same copy",
       %{conn: conn} do
    admin = admin_fixture(%{nickname: "athlete_program_admin"})
    %{organization: organization, context: context} = tenant_fixture(admin, "Athlete Program Gym")
    athlete = user_fixture(%{nickname: "profile_program_athlete", role: :athlete})
    add_membership(organization, athlete, :athlete)
    workout = tenant_workout_fixture(admin, context, %{title: "Athlete-only WOD"})
    provision_programming_entitlement(context, athlete)
    admin_conn = put_bearer_token(conn, admin)
    day = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()

    folder =
      admin_conn
      |> post(
        "/api/org/#{organization.slug}/admin/workout-folders",
        %{name: "Athlete Plans", parent_id: nil}
      )
      |> json_response(201)

    programmed =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/users/#{athlete.id}/programming",
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
      |> get(
        "/api/org/#{organization.slug}/admin/users/#{athlete.id}/schedule?start_date=#{day}&end_date=#{day}"
      )
      |> json_response(200)

    assert [%{"kind" => "assignment", "workout" => %{"id" => workout_id}}] = schedule["items"]
    assert workout_id == workout.id
  end

  describe "self-organising library folders" do
    test "every gym gets Athletes and Classes folders plus one folder per athlete",
         %{conn: conn} do
      admin = admin_fixture(%{nickname: "folders_admin"})
      %{organization: organization} = tenant_fixture(admin, "Folders Gym")
      athlete = user_fixture(%{nickname: "folders_athlete", role: :athlete})
      add_membership(organization, athlete, :athlete)

      other_admin = admin_fixture(%{nickname: "folders_other_admin"})
      %{organization: other_organization} = tenant_fixture(other_admin, "Other Folders Gym")

      folders = list_folders(conn, admin, organization)
      athletes = Enum.find(folders, &(&1["system_key"] == "athletes"))
      classes = Enum.find(folders, &(&1["system_key"] == "classes"))
      athlete_folder = Enum.find(folders, &(&1["system_key"] == "athlete:#{athlete.id}"))

      assert athletes["name"] == "Athletes" and athletes["parent_id"] == nil
      assert classes["name"] == "Classes" and classes["parent_id"] == nil
      assert athlete_folder["name"] == "folders_athlete"
      assert athlete_folder["parent_id"] == athletes["id"]

      # Root names are unique per gym, so a second gym gets its own system folders.
      other_folders = list_folders(conn, other_admin, other_organization)
      assert Enum.any?(other_folders, &(&1["system_key"] == "athletes"))
      refute Enum.any?(other_folders, &(&1["id"] == athletes["id"]))

      # Coaches can rename system folders; they are found by key, not recreated.
      conn
      |> put_bearer_token(admin)
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/workout-folders/#{athletes["id"]}",
        Jason.encode!(%{name: "Clients", parent_id: nil})
      )
      |> json_response(200)

      renamed = list_folders(conn, admin, organization)
      assert Enum.count(renamed, &(&1["system_key"] == "athletes")) == 1
      assert Enum.find(renamed, &(&1["system_key"] == "athletes"))["name"] == "Clients"
      assert length(renamed) == length(folders)
    end

    test "class folders are created only when a workout is assigned; same-day classes share a copy",
         %{conn: conn} do
      admin = admin_fixture(%{nickname: "class_filing_admin"})
      %{organization: organization, context: context} = tenant_fixture(admin, "Class Filing Gym")
      placeholder = tenant_workout_fixture(admin, context, %{title: "Placeholder"})
      template = tenant_workout_fixture(admin, context, %{title: "Daily Template"})
      class_type = class_type_fixture(%{name: "Filing Class", tenant_context: context})
      scheduled_at = ~U[2031-03-04 09:00:00Z]
      evening_at = DateTime.add(scheduled_at, 8 * 3_600)

      morning =
        create_slot(conn, admin, organization, placeholder.id, class_type.id, scheduled_at)

      evening = create_slot(conn, admin, organization, placeholder.id, class_type.id, evening_at)

      # Scheduling classes alone leaves the Classes tree empty.
      assert morning["master_workout_id"] == placeholder.id

      refute conn
             |> list_folders(admin, organization)
             |> Enum.any?(&String.starts_with?(&1["system_key"] || "", "classes:"))

      morning =
        assign_slot_workout(conn, admin, organization, morning, template.id, class_type.id)

      evening =
        assign_slot_workout(conn, admin, organization, evening, template.id, class_type.id)

      refute morning["master_workout_id"] == template.id
      assert evening["master_workout_id"] == morning["master_workout_id"]

      folders = list_folders(conn, admin, organization)
      by_key = Map.new(folders, &{&1["system_key"], &1})

      assert by_key["classes:2031"]["parent_id"] == by_key["classes"]["id"]
      assert by_key["classes:2031-03"]["name"] == "03"
      assert by_key["classes:2031-03"]["parent_id"] == by_key["classes:2031"]["id"]
      assert by_key["classes:2031-03-04"]["parent_id"] == by_key["classes:2031-03"]["id"]

      copy = workout_by_id(conn, admin, organization, morning["master_workout_id"])
      assert copy["folder_id"] == by_key["classes:2031-03-04"]["id"]
      assert copy["source_workout_id"] == template.id
      assert copy["title"] == "Daily Template"
      assert copy["status"] == "published"
    end

    test "new drafts can start inside a folder and workouts can be copied between folders",
         %{conn: conn} do
      admin = admin_fixture(%{nickname: "copy_admin"})
      %{organization: organization, context: context} = tenant_fixture(admin, "Copy Gym")
      workout = tenant_workout_fixture(admin, context, %{title: "Benchmark"})
      admin_conn = put_bearer_token(conn, admin)

      folder =
        admin_conn
        |> post("/api/org/#{organization.slug}/admin/workout-folders", %{name: "Benchmarks"})
        |> json_response(201)

      draft =
        admin_conn
        |> recycle()
        |> put_bearer_token(admin)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts",
          Jason.encode!(%{folder_id: folder["id"]})
        )
        |> json_response(201)
        |> Map.fetch!("draft")

      assert workout_by_id(conn, admin, organization, draft["id"])["folder_id"] == folder["id"]

      copied =
        admin_conn
        |> recycle()
        |> put_bearer_token(admin)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{workout.id}/copy",
          Jason.encode!(%{folder_id: folder["id"]})
        )
        |> json_response(201)
        |> Map.fetch!("workout")

      assert copied["title"] == "Benchmark"
      assert copied["status"] == "published"
      assert copied["folder_id"] == folder["id"]

      # A copy next to its original is labelled so the two can be told apart.
      same_folder =
        admin_conn
        |> recycle()
        |> put_bearer_token(admin)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{workout.id}/copy",
          Jason.encode!(%{folder_id: nil})
        )
        |> json_response(201)
        |> Map.fetch!("workout")

      assert same_folder["title"] == "Benchmark (copy)"
      assert same_folder["folder_id"] == nil
    end

    test "athlete profile programming files the workout in the athlete's folder by default",
         %{conn: conn} do
      admin = admin_fixture(%{nickname: "auto_folder_admin"})
      %{organization: organization, context: context} = tenant_fixture(admin, "Auto Folder Gym")
      athlete = user_fixture(%{nickname: "auto_folder_athlete", role: :athlete})
      add_membership(organization, athlete, :athlete)
      provision_programming_entitlement(context, athlete)
      template = tenant_workout_fixture(admin, context, %{title: "Engine"})

      programmed =
        conn
        |> put_bearer_token(admin)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/users/#{athlete.id}/programming",
          Jason.encode!(%{
            master_workout_id: template.id,
            scheduled_for: Date.utc_today() |> Date.to_iso8601(),
            copy_source: true
          })
        )
        |> json_response(201)

      athlete_folder =
        conn
        |> list_folders(admin, organization)
        |> Enum.find(&(&1["system_key"] == "athlete:#{athlete.id}"))

      assert programmed["workout"]["folder_id"] == athlete_folder["id"]
      assert programmed["workout"]["source_workout_id"] == template.id
      assert programmed["workout"]["title"] == "Engine"
    end
  end

  describe "workout icons" do
    test "published workouts get an AI icon unless a coach picked one", %{conn: conn} do
      admin = admin_fixture(%{nickname: "icon_admin"})
      %{organization: organization, context: context} = tenant_fixture(admin, "Icon Gym")
      deload = tenant_workout_fixture(admin, context, %{title: "Deload day"})
      chatty = tenant_workout_fixture(admin, context, %{title: "Chatty WOD"})

      assert {:ok, "💆"} = SuggestWorkoutIcon.call(context, deload.id)

      assert %{"icon" => "💆", "icon_source" => "ai"} =
               workout_by_id(conn, admin, organization, deload.id)

      # Model output that is not a single emoji is never stored.
      assert {:ok, :skipped} = SuggestWorkoutIcon.call(context, chatty.id)
      assert workout_by_id(conn, admin, organization, chatty.id)["icon"] == nil

      # A coach's choice wins and survives later suggestions.
      assert %{"icon" => "🔥", "icon_source" => "coach"} =
               set_icon(conn, admin, organization, deload.id, "🔥") |> json_response(200)

      assert {:ok, :kept_coach_icon} = SuggestWorkoutIcon.call(context, deload.id)
      assert workout_by_id(conn, admin, organization, deload.id)["icon"] == "🔥"

      assert %{"code" => "invalid_workout_icon"} =
               set_icon(conn, admin, organization, deload.id, "fire") |> json_response(422)

      # Resetting to automatic asks for a fresh suggestion.
      set_icon(conn, admin, organization, deload.id, nil) |> json_response(200)

      assert %{"icon" => "💆", "icon_source" => "ai"} =
               workout_by_id(conn, admin, organization, deload.id)

      # Copies keep their original's icon.
      copied =
        conn
        |> recycle()
        |> put_bearer_token(admin)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{deload.id}/copy",
          Jason.encode!(%{folder_id: nil})
        )
        |> json_response(201)
        |> Map.fetch!("workout")

      assert copied["icon"] == "💆"
    end
  end

  defp set_icon(conn, admin, organization, workout_id, icon) do
    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{organization.slug}/admin/workouts/#{workout_id}/icon",
      Jason.encode!(%{icon: icon})
    )
  end

  defp list_folders(conn, admin, organization) do
    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> get("/api/org/#{organization.slug}/admin/workout-folders")
    |> json_response(200)
    |> Map.fetch!("folders")
  end

  defp workout_by_id(conn, admin, organization, id) do
    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> get("/api/org/#{organization.slug}/admin/workouts")
    |> json_response(200)
    |> Map.fetch!("workouts")
    |> Enum.find(&(&1["id"] == id))
  end

  defp assign_slot_workout(conn, admin, organization, slot, workout_id, class_type_id) do
    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{organization.slug}/admin/schedule/slots/#{slot["id"]}",
      Jason.encode!(%{
        master_workout_id: workout_id,
        class_type_id: class_type_id,
        name: slot["name"],
        duration_minutes: slot["duration_minutes"],
        scheduled_at: slot["scheduled_at"],
        capacity: slot["capacity"],
        auto_approve: slot["auto_approve"],
        booking_timeout_minutes: slot["booking_timeout_minutes"]
      })
    )
    |> json_response(200)
    |> Map.fetch!("slot")
  end

  defp create_slot(conn, admin, organization, workout_id, class_type_id, scheduled_at) do
    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> put_req_header("content-type", "application/json")
    |> post(
      "/api/org/#{organization.slug}/admin/schedule/slots",
      Jason.encode!(%{
        master_workout_id: workout_id,
        class_type_id: class_type_id,
        name: "Filed Class",
        duration_minutes: 60,
        scheduled_at: scheduled_at,
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 30
      })
    )
    |> json_response(201)
    |> Map.fetch!("slot")
  end

  defp tenant_fixture(admin, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

    %{organization: organization, context: context}
  end

  defp add_membership(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    :ok
  end

  defp tenant_workout_fixture(admin, context, attrs) do
    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

    workout_fixture(admin, attrs)
  end

  defp provision_programming_entitlement(context, athlete) do
    code = "profile-programming-#{System.unique_integer([:positive])}"

    {:ok, package} =
      Finance.create_package(context, %{
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
      Finance.upsert_membership(context, athlete.id, %{
        user_type_snapshot: "athlete",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(context, membership.id, package.id, %{
        starts_on: Date.utc_today()
      })
  end
end
