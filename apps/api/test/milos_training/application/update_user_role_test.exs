defmodule MilosTraining.Application.UpdateUserRoleTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.{AssignWorkout, SubmitBooking, UpdateUserRole}
  alias MilosTraining.{Scheduling, Workouts}
  alias MilosTraining.TestFixtures

  test "member to athlete cancels active future bookings" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: false})

    assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
    assert booking.status == :pending

    assert {:ok, updated} = UpdateUserRole.call(member.id, %{"role" => "athlete"})
    assert updated.role == :athlete
    assert Scheduling.get_booking(booking.id) == nil
  end

  test "athlete to member archives active assignment access while retaining history" do
    admin = TestFixtures.admin_fixture()
    athlete = TestFixtures.user_fixture(%{role: :athlete})
    workout = TestFixtures.workout_fixture(admin)

    assert {:ok, assignment} =
             AssignWorkout.call(%{
               master_workout_id: workout.id,
               scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
               athlete_ids: [athlete.id],
               admin_notes: "Role transition coverage"
             })

    assert Workouts.get_assignment_execution_access(assignment.id, athlete.id)

    assert {:ok, updated} = UpdateUserRole.call(athlete.id, %{"role" => "member"})
    assert updated.role == :member
    assert Workouts.get_assignment_execution_access(assignment.id, athlete.id) == nil
    assert Workouts.get_assigned_workout(assignment.id).athlete_ids == [athlete.id]
  end
end
