defmodule PaleeWeb.AdminAssignedWorkoutControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, TestFixtures}

  test "admin can assign a workout to multiple athletes", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "admin_assign_controller"})
    athlete_one = TestFixtures.user_fixture(%{nickname: "assign_controller_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "assign_controller_two", role: :athlete})
    organization = tenant_organization_fixture(admin, "Assigned Workout Gym")
    add_athlete_membership(organization, athlete_one)
    add_athlete_membership(organization, athlete_two)
    workout = tenant_workout_fixture(admin, organization, %{title: "Assign Controller WOD"})

    response =
      conn
      |> put_bearer_token(admin)
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/assigned-workouts",
        Jason.encode!(%{
          master_workout_id: workout.id,
          athlete_ids: [athlete_one.id, athlete_two.id],
          scheduled_for: Date.utc_today()
        })
      )
      |> json_response(201)

    # Each athlete gets their own copy of the library workout, filed in their folder.
    assert [_, _] = assignments = response["assignments"]
    assert response["assignment"] == hd(assignments)

    assert assignments |> Enum.flat_map(& &1["athlete_ids"]) |> MapSet.new() ==
             MapSet.new([athlete_one.id, athlete_two.id])

    admin_conn = conn |> recycle() |> put_bearer_token(admin)

    folders =
      admin_conn
      |> get("/api/org/#{organization.slug}/admin/workout-folders")
      |> json_response(200)
      |> Map.fetch!("folders")

    workouts_by_id =
      admin_conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/workouts")
      |> json_response(200)
      |> Map.fetch!("workouts")
      |> Map.new(&{&1["id"], &1})

    athletes_root = Enum.find(folders, &(&1["system_key"] == "athletes"))

    for assignment <- assignments do
      [athlete_id] = assignment["athlete_ids"]
      copy = Map.fetch!(workouts_by_id, assignment["master_workout_id"])
      folder = Enum.find(folders, &(&1["system_key"] == "athlete:#{athlete_id}"))

      refute copy["id"] == workout.id
      assert copy["source_workout_id"] == workout.id
      assert copy["title"] == "Assign Controller WOD"
      assert copy["folder_id"] == folder["id"]
      assert folder["parent_id"] == athletes_root["id"]
    end

    assert Map.fetch!(workouts_by_id, workout.id)["folder_id"] == nil
  end

  test "assigning an athlete a workout already in their folder does not copy it",
       %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "admin_assign_in_folder"})
    athlete = TestFixtures.user_fixture(%{nickname: "assign_in_folder_athlete", role: :athlete})
    organization = tenant_organization_fixture(admin, "Assign In Folder Gym")
    add_athlete_membership(organization, athlete)
    workout = tenant_workout_fixture(admin, organization, %{title: "Personal WOD"})
    admin_conn = put_bearer_token(conn, admin)

    athlete_folder =
      admin_conn
      |> get("/api/org/#{organization.slug}/admin/workout-folders")
      |> json_response(200)
      |> Map.fetch!("folders")
      |> Enum.find(&(&1["system_key"] == "athlete:#{athlete.id}"))

    admin_conn
    |> recycle()
    |> put_bearer_token(admin)
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{organization.slug}/admin/workouts/#{workout.id}/library",
      Jason.encode!(%{folder_id: athlete_folder["id"]})
    )
    |> json_response(200)

    response =
      admin_conn
      |> recycle()
      |> put_bearer_token(admin)
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/assigned-workouts",
        Jason.encode!(%{
          master_workout_id: workout.id,
          athlete_ids: [athlete.id],
          scheduled_for: Date.utc_today()
        })
      )
      |> json_response(201)

    assert response["assignment"]["master_workout_id"] == workout.id
  end

  test "admin can inline update assignment date and athletes", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "admin_update_assignment"})
    athlete_one = TestFixtures.user_fixture(%{nickname: "update_assignment_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "update_assignment_two", role: :athlete})
    organization = tenant_organization_fixture(admin, "Assignment Update Gym")
    add_athlete_membership(organization, athlete_one)
    add_athlete_membership(organization, athlete_two)
    workout = tenant_workout_fixture(admin, organization, %{title: "Update Assignment WOD"})

    assignment =
      conn
      |> put_bearer_token(admin)
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/assigned-workouts",
        Jason.encode!(%{
          master_workout_id: workout.id,
          athlete_ids: [athlete_one.id],
          scheduled_for: Date.utc_today()
        })
      )
      |> json_response(201)
      |> Map.fetch!("assignment")

    updated_date = Date.add(Date.utc_today(), 1)

    response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/assigned-workouts/#{assignment["id"]}",
        Jason.encode!(%{
          athlete_ids: [athlete_one.id, athlete_two.id],
          scheduled_for: updated_date,
          instructions: "Updated plan"
        })
      )
      |> json_response(200)

    assert response["assignment"]["scheduled_for"] == Date.to_iso8601(updated_date)

    assert MapSet.new(response["assignment"]["athlete_ids"]) ==
             MapSet.new([athlete_one.id, athlete_two.id])
  end

  defp tenant_organization_fixture(admin, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    organization
  end

  defp add_athlete_membership(organization, athlete) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    :ok
  end

  defp tenant_workout_fixture(admin, organization, attrs) do
    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

    Palee.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Palee.Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

    TestFixtures.workout_fixture(admin, attrs)
  end
end
