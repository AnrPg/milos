defmodule MilosTraining.Application.DeleteWorkoutPreservesExecutionTest do
  use MilosTraining.DataCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.DeleteWorkout
  alias MilosTraining.Execution
  alias MilosTraining.Repo
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.ClassSeries
  alias MilosTraining.Scheduling.ScheduledClass

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

  test "deleting a workout deletes recurring class series and generated slots" do
    admin = admin_fixture()
    workout = workout_fixture(admin)
    class_type = class_type_fixture()
    starts_on = Date.add(Date.utc_today(), 1)

    assert {:ok, series} =
             Scheduling.create_class_series(%{
               master_workout_id: workout.id,
               class_type_id: class_type.id,
               name: "Cleanup series",
               duration_minutes: 60,
               timezone: "Etc/UTC",
               starts_on: starts_on,
               ends_on: starts_on,
               local_start_time: ~T[12:00:00],
               weekdays: [Date.day_of_week(starts_on)],
               capacity: 10,
               auto_approve: false,
               booking_timeout_minutes: 60
             })

    assert Repo.get(ClassSeries, series.id)
    assert slot_count(workout.id) > 0

    assert :ok = DeleteWorkout.call(workout.id)

    refute Repo.get(ClassSeries, series.id)
    assert slot_count(workout.id) == 0
  end

  defp slot_count(workout_id) do
    ScheduledClass
    |> where([slot], slot.master_workout_id == ^workout_id)
    |> Repo.aggregate(:count)
  end
end
