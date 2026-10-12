defmodule MilosTraining.Workers.ProcessWorkoutCompletionJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Application.{CompleteWorkout, LogTrainingEntry, VoidTrainingLogEntry}
  alias MilosTraining.Gamification
  alias MilosTraining.Execution
  alias MilosTraining.Organizations
  alias MilosTraining.Repo
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

  # `workout_fixture/1` creates workouts through the unscoped
  # `Workouts.create_workout/2` path, so the row lands with whatever
  # organization the DB column default assigns (the seeded legacy
  # organization). Reading it back through `Workouts.get_workout/1` is
  # tenant-scoped, so tests that need to look the workout up (e.g. via
  # `Execution.start_execution/2`) — and executions back up through
  # `Execution.get_execution/1`, which is scoped by `app.user_id` — must set
  # that same organization/user context in the session first.
  defp set_legacy_tenant_context!(user) do
    legacy_organization = Organizations.get_by_slug(Organizations.legacy_organization_slug())

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", user.id])
    :ok
  end

  test "completion is acknowledged only after a durable processing job is enqueued" do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})
    workout = workout_fixture(admin)
    set_legacy_tenant_context!(member)

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

  test "the enqueued job successfully processes the completion instead of cancelling with :execution_not_found" do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})
    workout = workout_fixture(admin)
    set_legacy_tenant_context!(member)

    assert {:ok, execution} =
             Execution.start_execution(member.id, %{
               master_workout_id: workout.id,
               source: :self_selected,
               started_at_utc: DateTime.utc_now(),
               started_at_tz: "UTC"
             })

    assert {:ok, _completed} = CompleteWorkout.call(execution.id, member.id, %{})

    assert :ok =
             perform_job(ProcessWorkoutCompletionJob, %{"execution_id" => execution.id})
  end

  describe "standalone training-log completions (ADR-108)" do
    defp training_log_member_context do
      owner = admin_fixture()
      member = user_fixture(%{role: :member})

      {:ok, organization} =
        Organizations.create_organization(%{
          name: "Job Gym #{System.unique_integer([:positive])}"
        })

      for {user, role} <- [{owner, :owner}, {member, :member}] do
        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, context} = Organizations.resolve_tenant_context(member, organization.slug)
      {member, context}
    end

    defp freeform_log_params do
      %{
        "source_type" => "freeform",
        "title" => "Park run",
        "performed_at" => DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
        "idempotency_key" => "job-" <> Ecto.UUID.generate()
      }
    end

    test "logging enqueues the shared completion job with a training_log source flag" do
      {member, context} = training_log_member_context()

      assert {:ok, entry, :created} =
               LogTrainingEntry.call(context, member, freeform_log_params())

      args = %{
        "source" => "training_log",
        "training_log_entry_id" => entry.id,
        "organization_id" => entry.organization_id,
        "user_id" => member.id
      }

      assert_enqueued(worker: ProcessWorkoutCompletionJob, args: args)
      assert :ok = perform_job(ProcessWorkoutCompletionJob, args)
      assert %{total_workouts: 1} = Gamification.get_user_stats(member.id)
    end

    test "a job for a voided entry cancels instead of crashing or counting" do
      {member, context} = training_log_member_context()
      {:ok, entry, :created} = LogTrainingEntry.call(context, member, freeform_log_params())
      {:ok, _voided} = VoidTrainingLogEntry.call(context, member, entry.id, %{})

      assert {:cancel, :training_log_entry_voided} =
               perform_job(ProcessWorkoutCompletionJob, %{
                 "source" => "training_log",
                 "training_log_entry_id" => entry.id,
                 "organization_id" => entry.organization_id,
                 "user_id" => member.id
               })

      assert Gamification.get_user_stats(member.id) == nil
    end
  end
end
