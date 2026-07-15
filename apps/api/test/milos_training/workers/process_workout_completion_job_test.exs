defmodule MilosTraining.Workers.ProcessWorkoutCompletionJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Application.CompleteWorkout
  alias MilosTraining.Execution
  alias MilosTraining.Workers.ProcessWorkoutCompletionJob

  import MilosTraining.TestFixtures

  setup do
    previous = Application.get_env(:milos_training, :start_oban)
    Application.put_env(:milos_training, :start_oban, true)

    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    on_exit(fn -> Application.put_env(:milos_training, :start_oban, previous) end)
    :ok
  end

  test "completion is acknowledged only after a durable processing job is enqueued" do
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

    assert {:ok, completed} = CompleteWorkout.call(execution.id, member.id, %{})
    assert completed.status == "completed"

    assert_enqueued(
      worker: ProcessWorkoutCompletionJob,
      args: %{"execution_id" => execution.id}
    )
  end
end
