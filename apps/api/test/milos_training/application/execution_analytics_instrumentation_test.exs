defmodule MilosTraining.Application.ExecutionAnalyticsInstrumentationTest do
  @moduledoc "ADR-113: execution start/complete/abandon and training-log events."
  use MilosTraining.DataCase, async: false

  import Ecto.Query
  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{
    CompleteWorkout,
    LogTrainingEntry,
    StartWorkoutExecution,
    SweepAbandonedExecutions,
    VoidTrainingLogEntry
  }

  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Repo, Workouts}

  defp scoreable_workout(context, owner) do
    {:ok, workout} =
      Workouts.create_workout(context, owner, %{
        title: "Analytics WOD #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: true,
            score_config: %{type: "time", unit: "seconds"},
            exercises: [
              %{
                name: "Burpees",
                order: 1,
                sets: 3,
                prescription_value: 10,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      })

    workout
  end

  defp start!(member_context, member, workout) do
    {:ok, execution} =
      StartWorkoutExecution.call(member_context, member, %{
        "master_workout_id" => workout.id,
        "source" => "self_selected"
      })

    execution
  end

  defp backdate!(execution_id, hours, extra \\ []) do
    started_at = DateTime.add(DateTime.utc_now(), -hours * 3_600, :second)

    {1, _} =
      WorkoutExecution
      |> where([e], e.id == ^execution_id)
      |> Repo.update_all(set: [started_at_utc: started_at] ++ extra)
  end

  test "start and completion record score-capture facts" do
    {organization, owner, context} = organization_fixture()
    {member, member_context} = member_context(organization)
    workout = scoreable_workout(context, owner)

    execution = start!(member_context, member, workout)

    started = analytics_event!(organization.id, "workout_execution_started")
    assert started.user_id == member.id
    assert started.context_id == execution.id
    assert started.metadata["source"] == "self_selected"
    assert started.metadata["master_workout_id"] == workout.id

    assert {:ok, completed} =
             CompleteWorkout.call(member_context, execution.id, member.id, %{
               "total_elapsed_ms" => 60_000,
               "section_scores" => []
             })

    event = analytics_event!(organization.id, "workout_execution_completed")
    assert event.context_id == completed.id
    assert event.user_id == member.id

    for key <- ~w(duration_ms total_elapsed_ms segment_count scoreable_section_count
                  manually_scored_section_count auto_scored_section_count source) do
      assert Map.has_key?(event.metadata, key), "missing #{key}"
    end

    assert event.metadata["scoreable_section_count"] == 1
    assert event.metadata["manually_scored_section_count"] == 0
  end

  test "abandonment sweep honours the threshold and records once per execution" do
    {organization, owner, context} = organization_fixture()
    {member, member_context} = member_context(organization)
    workout = scoreable_workout(context, owner)

    stale = start!(member_context, member, workout)
    fresh = start!(member_context, member, workout)
    finished = start!(member_context, member, workout)

    {:ok, _} =
      CompleteWorkout.call(member_context, finished.id, member.id, %{"section_scores" => []})

    backdate!(stale.id, 7, status: :paused)
    backdate!(fresh.id, 2)
    backdate!(finished.id, 7)

    # Another tenant's stale execution is never swept from this tenant.
    {other_org, other_owner, other_context} = organization_fixture()
    {other_member, other_member_context} = member_context(other_org)

    other =
      start!(other_member_context, other_member, scoreable_workout(other_context, other_owner))

    backdate!(other.id, 7)

    assert {:ok, 1} = SweepAbandonedExecutions.call(organization.id)
    assert {:ok, 0} = SweepAbandonedExecutions.call(organization.id)

    event = analytics_event!(organization.id, "workout_execution_abandoned")
    assert event.context_id == stale.id
    assert event.user_id == member.id
    assert event.dedupe_key == stale.id
    assert event.metadata["status"] == "paused"
    assert event.metadata["abandon_segment_index"] == 0
    assert event.metadata["abandon_format"]
    assert event.metadata["threshold_hours"] == 6
    assert event.metadata["hours_since_start"] == 7
    assert analytics_events(other_org.id, "workout_execution_abandoned") == []

    # A larger threshold excludes it; a smaller one would pick up the fresh one.
    assert {:ok, 0} =
             SweepAbandonedExecutions.call(other_org.id, DateTime.utc_now(), threshold_hours: 8)

    assert {:ok, 1} =
             SweepAbandonedExecutions.call(organization.id, DateTime.utc_now(),
               threshold_hours: 1
             )

    assert length(analytics_events(organization.id, "workout_execution_abandoned")) == 2
  end

  test "training-log entries record logged and voided once" do
    {organization, _owner, _context} = organization_fixture()
    {member, member_context} = member_context(organization)

    params = %{
      "source_type" => "freeform",
      "title" => "Hotel gym session",
      "performed_at" => DateTime.utc_now() |> DateTime.add(-86_400) |> DateTime.to_iso8601(),
      "duration_seconds" => 1800,
      "perceived_effort" => 6,
      "idempotency_key" => Ecto.UUID.generate()
    }

    assert {:ok, entry, :created} = LogTrainingEntry.call(member_context, member, params)
    assert {:ok, _replay, :replayed} = LogTrainingEntry.call(member_context, member, params)

    logged = analytics_event!(organization.id, "training_log_entry_logged")
    assert logged.context_id == entry.id
    assert logged.metadata["source_type"] == "freeform"
    assert logged.metadata["duration_seconds"] == 1800
    refute Map.has_key?(logged.metadata, "title")

    assert {:ok, _voided} = VoidTrainingLogEntry.call(member_context, member, entry.id, %{})
    assert analytics_event!(organization.id, "training_log_entry_voided").context_id == entry.id
  end

  test "the hourly cron job sweeps every active tenant idempotently" do
    {organization, owner, context} = organization_fixture()
    {member, member_context} = member_context(organization)
    stale = start!(member_context, member, scoreable_workout(context, owner))
    backdate!(stale.id, 9)

    assert :ok = MilosTraining.Workers.ExecutionAbandonmentSweepJob.perform(%Oban.Job{args: %{}})
    assert :ok = MilosTraining.Workers.ExecutionAbandonmentSweepJob.perform(%Oban.Job{args: %{}})

    assert analytics_event!(organization.id, "workout_execution_abandoned").context_id == stale.id
  end
end
