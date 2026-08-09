defmodule MilosTraining.Application.DeleteWorkoutPreservesExecutionTest do
  use MilosTraining.DataCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.DeleteWorkout
  alias MilosTraining.Execution
  alias MilosTraining.Organizations
  alias MilosTraining.Repo
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.ClassSeries
  alias MilosTraining.Scheduling.ScheduledClass

  test "deleting a workout preserves completed execution history" do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})
    context = tenant_context_fixture(admin, "Delete Workout History Gym")
    set_tenant_session!(context, member.id)
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
    context = tenant_context_fixture(admin, "Delete Workout Series Gym")
    set_tenant_session!(context, admin.id)
    workout = workout_fixture(admin)
    class_type = class_type_fixture(%{tenant_context: context})
    starts_on = Date.add(Date.utc_today(), 1)

    assert {:ok, series} =
             Scheduling.create_class_series(context, %{
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

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end

  defp set_tenant_session!(context, user_id) do
    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", user_id])
  end
end
