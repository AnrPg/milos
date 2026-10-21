defmodule MilosTraining.Application.GoalFeedbackSummaryTest do
  @moduledoc """
  ADR-163 coach totals of «τι ένιωσες» per workout and per scheduled class:
  the three-entry threshold, roll-up to muscle groups, goals nobody felt,
  voided entries and class membership of entries. (Row security is covered
  by `GoalFeedbackSummaryRLSTest` and the controller test.)
  """
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{GetGoalFeedbackSummary, SaveWorkoutGoals}
  alias MilosTraining.Execution.{TrainingLogEntry, WorkoutExecution}
  alias MilosTraining.Journal.GoalFeedback
  alias MilosTraining.Scheduling.Booking
  alias MilosTraining.TestFixtures

  setup do
    {org, owner, staff} = organization_fixture()
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: staff})

    {:ok, _} =
      SaveWorkoutGoals.call(staff, workout.id, %{
        "muscles" => [
          %{"id" => "quadriceps", "role" => "primary"},
          %{"id" => "gluteus-maximus", "role" => "secondary"},
          %{"id" => "rectus-abdominis", "role" => "stabilizer"},
          %{"id" => "hamstrings", "role" => "secondary"}
        ],
        "qualities" => ["strength"]
      })

    %{org: org, owner: owner, staff: staff, workout: workout}
  end

  defp execution(ctx, user, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %WorkoutExecution{
          user_id: user.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.workout.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  defp log_entry(ctx, user, attrs) do
    Repo.insert!(
      struct(
        %TrainingLogEntry{
          user_id: user.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.workout.id,
          source_type: "library_workout",
          source_reference_id: ctx.workout.id,
          title: "WOD",
          performed_at_utc: DateTime.utc_now(),
          idempotency_key: Ecto.UUID.generate()
        },
        attrs
      )
    )
  end

  defp felt(ctx, kind, entry, muscles, qualities \\ []) do
    Repo.insert!(%GoalFeedback{
      user_id: entry.user_id,
      organization_id: ctx.org.id,
      entry_kind: kind,
      entry_id: entry.id,
      felt_muscles: muscles,
      felt_qualities: qualities
    })
  end

  defp member(ctx) do
    {user, _context} = member_context(ctx.org)
    user
  end

  describe "workout totals" do
    test "nothing but the count below three entries", ctx do
      felt(ctx, "execution", execution(ctx, member(ctx)), ["quadriceps"], ["strength"])
      felt(ctx, "execution", execution(ctx, member(ctx)), ["quadriceps"])

      assert {:ok, summary} = GetGoalFeedbackSummary.for_workout(ctx.staff, ctx.workout.id)

      assert summary == %{
               workout_id: ctx.workout.id,
               entries: 2,
               shown: false,
               felt_muscles: [],
               felt_qualities: [],
               goals_not_felt: []
             }
    end

    test "from three entries: groups counted once per entry, goals nobody felt", ctx do
      # A head and its group in one entry count the group once.
      felt(ctx, "execution", execution(ctx, member(ctx)), ["rectus-femoris", "quadriceps"], [
        "strength"
      ])

      felt(ctx, "execution", execution(ctx, member(ctx)), ["vastus-lateralis"], ["strength"])

      felt(ctx, "training_log", log_entry(ctx, member(ctx), %{}), ["gluteus-maximus"], [
        "power"
      ])

      assert {:ok, summary} = GetGoalFeedbackSummary.for_workout(ctx.staff, ctx.workout.id)

      assert summary.entries == 3 and summary.shown
      assert summary.felt_muscles == [%{id: "quadriceps", count: 2}, %{id: "glutes", count: 1}]
      assert summary.felt_qualities == [%{id: "strength", count: 2}, %{id: "power", count: 1}]
      # Stabilizers are not expected to be felt.
      assert summary.goals_not_felt == ["hamstrings"]
    end

    test "voided entries and other workouts' entries do not count", ctx do
      felt(ctx, "execution", execution(ctx, member(ctx)), ["quadriceps"])
      felt(ctx, "execution", execution(ctx, member(ctx)), ["quadriceps"])

      voided =
        log_entry(ctx, member(ctx), %{status: "voided", voided_at: DateTime.utc_now()})

      felt(ctx, "training_log", voided, ["quadriceps"])

      other = TestFixtures.workout_fixture(ctx.owner, %{tenant_context: ctx.staff})
      felt(ctx, "execution", execution(ctx, member(ctx), %{master_workout_id: other.id}), [])

      assert {:ok, %{entries: 2, shown: false}} =
               GetGoalFeedbackSummary.for_workout(ctx.staff, ctx.workout.id)
    end

    test "another gym's workout is not found", ctx do
      {_org, _owner, other_staff} = organization_fixture()

      assert {:error, :not_found} =
               GetGoalFeedbackSummary.for_workout(other_staff, ctx.workout.id)

      assert {:error, :not_found} = GetGoalFeedbackSummary.for_workout(ctx.staff, "nope")
    end
  end

  describe "class totals" do
    setup ctx do
      TestFixtures.class_type_fixture(%{tenant_context: ctx.staff})
      slot = TestFixtures.slot_fixture(ctx.workout, %{tenant_context: ctx.staff})

      %{slot: slot}
    end

    defp booking(ctx, user) do
      Repo.insert!(%Booking{
        organization_id: ctx.org.id,
        scheduled_class_id: ctx.slot.id,
        user_id: user.id,
        status: :approved
      })
    end

    test "counts entries logged from the class or timed from its bookings", ctx do
      # A member's own version of the class (another workout) still counts.
      variant = TestFixtures.workout_fixture(ctx.owner, %{tenant_context: ctx.staff})
      timed = member(ctx)

      felt(
        ctx,
        "execution",
        execution(ctx, timed, %{
          source: :class_booking,
          source_reference_id: booking(ctx, timed).id
        }),
        ["quadriceps"]
      )

      felt(
        ctx,
        "training_log",
        log_entry(ctx, member(ctx), %{source_type: "class", source_reference_id: ctx.slot.id}),
        ["quadriceps"]
      )

      felt(
        ctx,
        "training_log",
        log_entry(ctx, member(ctx), %{
          source_type: "class",
          source_reference_id: ctx.slot.id,
          master_workout_id: variant.id
        }),
        ["hamstrings"]
      )

      # Not from the class: the same workout done on its own.
      felt(ctx, "execution", execution(ctx, member(ctx)), ["gluteus-maximus"])

      assert {:ok, summary} = GetGoalFeedbackSummary.for_scheduled_class(ctx.staff, ctx.slot.id)

      assert summary.scheduled_class_id == ctx.slot.id
      assert summary.workout_id == ctx.workout.id
      assert summary.entries == 3 and summary.shown

      assert summary.felt_muscles == [
               %{id: "quadriceps", count: 2},
               %{id: "hamstrings", count: 1}
             ]

      assert summary.goals_not_felt == ["glutes"]
    end

    test "an unknown class is not found", ctx do
      assert {:error, :not_found} =
               GetGoalFeedbackSummary.for_scheduled_class(ctx.staff, Ecto.UUID.generate())
    end
  end
end
