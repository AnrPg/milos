defmodule MilosTraining.Application.GoalFeedbackSummaryRLSTest do
  @moduledoc """
  ADR-163 coach totals under real Row Level Security: only feedback on
  entries whose rung reaches the acting coach counts, so private entries
  never reach the totals (nor the three-entry threshold), and staff who
  are not coaches of the gym count nothing.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import Ecto.Query
  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.GetGoalFeedbackSummary
  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.Journal.GoalFeedback
  alias MilosTraining.TestFixtures

  setup do
    bypass_rls(fn ->
      {org, owner, staff} = organization_fixture()
      {_coach, coach_context} = member_context(org, :coach)
      {_other_org, _other_owner, other_staff} = organization_fixture()
      workout = TestFixtures.workout_fixture(owner, %{tenant_context: staff})

      for visibility <- ~w(coach_can_view coach_can_view coach_reply_requested private private) do
        {member, _context} = member_context(org)

        execution =
          Repo.insert!(%WorkoutExecution{
            user_id: member.id,
            organization_id: org.id,
            master_workout_id: workout.id,
            status: :completed,
            started_at_utc: DateTime.utc_now(),
            completed_at_utc: DateTime.utc_now(),
            journal_visibility: visibility
          })

        Repo.insert!(%GoalFeedback{
          user_id: member.id,
          organization_id: org.id,
          entry_kind: "execution",
          entry_id: execution.id,
          felt_muscles: [if(visibility == "private", do: "hamstrings", else: "quadriceps")],
          felt_qualities: ["stamina"]
        })
      end

      %{staff: staff, coach_context: coach_context, other_staff: other_staff, workout: workout}
    end)
  end

  test "a coach counts only the entries that reach them", ctx do
    assert {:ok, summary} = GetGoalFeedbackSummary.for_workout(ctx.coach_context, ctx.workout.id)

    assert summary.entries == 3 and summary.shown
    assert summary.felt_muscles == [%{id: "quadriceps", count: 3}]
    assert summary.felt_qualities == [%{id: "stamina", count: 3}]
  end

  test "a private entry never fills the threshold", ctx do
    bypass_rls(fn ->
      Repo.update_all(
        from(e in WorkoutExecution, where: e.journal_visibility == "coach_reply_requested"),
        set: [journal_visibility: "private"]
      )
    end)

    assert {:ok, %{entries: 2, shown: false, felt_muscles: []}} =
             GetGoalFeedbackSummary.for_workout(ctx.coach_context, ctx.workout.id)
  end

  test "staff who are not coaches of the gym count nothing", ctx do
    # The owner holds no coach role here.
    assert {:ok, %{entries: 0, shown: false}} =
             GetGoalFeedbackSummary.for_workout(ctx.staff, ctx.workout.id)

    assert {:error, :not_found} =
             GetGoalFeedbackSummary.for_workout(ctx.other_staff, ctx.workout.id)
  end
end
