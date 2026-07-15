defmodule MilosTraining.Application.DeleteWorkoutPreservesExecutionTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.DeleteWorkout
  alias MilosTraining.Execution

  import MilosTraining.TestFixtures

  test "deleting a workout preserves completed execution history" do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})
    workout = workout_fixture(admin)

    assert {:ok, execution} =
             Execution.start_execution(member.id, %{
               master_workout_id: workout.id,
               source: :self_selected,
               started_at_utc: DateTime.utc_now(),
               started_at_tz: "UTC"
             })

    assert {:ok, _completed} =
             Execution.complete_execution(execution.id, member.id, %{
               completed_at_utc: DateTime.utc_now(),
               completed_at_tz: "UTC",
               status: :completed
             })

    assert :ok = DeleteWorkout.call(workout.id)

    preserved = Execution.get_execution(execution.id)
    assert preserved.status == "completed"
    assert preserved.master_workout_id == nil
  end
end
