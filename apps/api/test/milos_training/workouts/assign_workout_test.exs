defmodule MilosTraining.Workouts.AssignWorkoutTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.AssignWorkout
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workouts

  defp tenant_context_fixture(admin, name) do
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
    context
  end

  defp athlete_membership_fixture(context, athlete) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: context.organization_id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    athlete
  end

  defp tenant_workout_fixture(context, admin) do
    params = %{
      title: "Workout #{System.unique_integer([:positive])}",
      type: :crossfit,
      sections: [
        %{
          name: "Main Set",
          order: 1,
          scoreable: false,
          exercises: [
            %{
              name: "Air Squats",
              order: 1,
              sets: 3,
              prescription_value: 10,
              prescription_unit: "reps"
            }
          ]
        }
      ]
    }

    {:ok, workout} = Workouts.create_workout(context, admin, params)
    workout
  end

  test "assigns a published workout to multiple athletes" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_admin"})

    context =
      tenant_context_fixture(admin, "Assign Workout Gym #{System.unique_integer([:positive])}")

    athlete_one = TestFixtures.user_fixture(%{nickname: "athlete_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "athlete_two", role: :athlete})
    athlete_membership_fixture(context, athlete_one)
    athlete_membership_fixture(context, athlete_two)
    workout = tenant_workout_fixture(context, admin)

    assert {:ok, assignment} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [athlete_one.id, athlete_two.id],
               scheduled_for: Date.utc_today()
             })

    assert assignment.master_workout_id == workout.id
    assert MapSet.new(assignment.athlete_ids) == MapSet.new([athlete_one.id, athlete_two.id])
    assert assignment.workout.id == workout.id

    for athlete <- [athlete_one, athlete_two] do
      assert Enum.any?(
               MilosTraining.Notifications.list_for_user(athlete.id),
               &(&1.type == "workout_assigned")
             )
    end
  end

  test "merges repeat assignment requests for the same workout and date" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_merge_admin"})

    context =
      tenant_context_fixture(admin, "Assign Merge Gym #{System.unique_integer([:positive])}")

    athlete_one = TestFixtures.user_fixture(%{nickname: "assign_merge_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "assign_merge_two", role: :athlete})
    athlete_membership_fixture(context, athlete_one)
    athlete_membership_fixture(context, athlete_two)
    workout = tenant_workout_fixture(context, admin)
    scheduled_for = Date.utc_today()

    assert {:ok, first_assignment} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [athlete_one.id],
               scheduled_for: scheduled_for
             })

    assert {:ok, second_assignment} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [athlete_two.id],
               scheduled_for: scheduled_for
             })

    assert first_assignment.id == second_assignment.id

    assert MapSet.new(second_assignment.athlete_ids) ==
             MapSet.new([athlete_one.id, athlete_two.id])
  end

  test "rejects assignments that target non-athlete users" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_invalid_admin"})

    context =
      tenant_context_fixture(admin, "Assign Invalid Gym #{System.unique_integer([:positive])}")

    member = TestFixtures.user_fixture(%{nickname: "assign_member", role: :member})
    workout = tenant_workout_fixture(context, admin)

    assert {:error, :invalid_athletes} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [member.id],
               scheduled_for: Date.utc_today()
             })
  end

  test "lists an athlete week view scoped to their own assignments" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_scope_admin"})

    context =
      tenant_context_fixture(admin, "Assign Scope Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "assign_scope_athlete", role: :athlete})
    other_athlete = TestFixtures.user_fixture(%{nickname: "assign_scope_other", role: :athlete})
    athlete_membership_fixture(context, athlete)
    athlete_membership_fixture(context, other_athlete)
    workout = tenant_workout_fixture(context, admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    {:ok, _other_assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [other_athlete.id],
        scheduled_for: monday
      })

    assignments =
      Workouts.list_assigned_workouts_for_athlete(
        context,
        athlete.id,
        monday,
        Date.add(monday, 6)
      )

    assert length(assignments) == 1
    assert hd(assignments).athlete_ids == [athlete.id]
  end
end
