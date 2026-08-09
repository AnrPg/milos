defmodule MilosTrainingWeb.AdminAssignedWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Organizations, TestFixtures}

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

    assert response["assignment"]["master_workout_id"] == workout.id

    assert MapSet.new(response["assignment"]["athlete_ids"]) ==
             MapSet.new([athlete_one.id, athlete_two.id])
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
          admin_notes: "Updated plan"
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

    MilosTraining.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    MilosTraining.Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

    TestFixtures.workout_fixture(admin, attrs)
  end
end
