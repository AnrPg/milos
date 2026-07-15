defmodule MilosTraining.Workouts.AssignWorkoutTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.AssignWorkout
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workouts

  test "assigns a published workout to multiple athletes" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_admin"})
    athlete_one = TestFixtures.user_fixture(%{nickname: "athlete_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "athlete_two", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)

    assert {:ok, assignment} =
             AssignWorkout.call(%{
               master_workout_id: workout.id,
               athlete_ids: [athlete_one.id, athlete_two.id],
               scheduled_for: Date.utc_today()
             })

    assert assignment.master_workout_id == workout.id
    assert MapSet.new(assignment.athlete_ids) == MapSet.new([athlete_one.id, athlete_two.id])
    assert assignment.workout.id == workout.id
  end

  test "merges repeat assignment requests for the same workout and date" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_merge_admin"})
    athlete_one = TestFixtures.user_fixture(%{nickname: "assign_merge_one", role: :athlete})
    athlete_two = TestFixtures.user_fixture(%{nickname: "assign_merge_two", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)
    scheduled_for = Date.utc_today()

    assert {:ok, first_assignment} =
             AssignWorkout.call(%{
               master_workout_id: workout.id,
               athlete_ids: [athlete_one.id],
               scheduled_for: scheduled_for
             })

    assert {:ok, second_assignment} =
             AssignWorkout.call(%{
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
    member = TestFixtures.user_fixture(%{nickname: "assign_member", role: :member})
    workout = TestFixtures.workout_fixture(admin)

    assert {:error, :invalid_athletes} =
             AssignWorkout.call(%{
               master_workout_id: workout.id,
               athlete_ids: [member.id],
               scheduled_for: Date.utc_today()
             })
  end

  test "lists an athlete week view scoped to their own assignments" do
    admin = TestFixtures.admin_fixture(%{nickname: "assign_scope_admin"})
    athlete = TestFixtures.user_fixture(%{nickname: "assign_scope_athlete", role: :athlete})
    other_athlete = TestFixtures.user_fixture(%{nickname: "assign_scope_other", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    {:ok, _other_assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [other_athlete.id],
        scheduled_for: monday
      })

    assignments =
      Workouts.list_assigned_workouts_for_athlete(athlete.id, monday, Date.add(monday, 6))

    assert length(assignments) == 1
    assert hd(assignments).athlete_ids == [athlete.id]
  end
end
