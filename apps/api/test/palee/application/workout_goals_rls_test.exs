defmodule Palee.Application.WorkoutGoalsRLSTest do
  @moduledoc """
  ADR-163 under real Row Level Security: workout goals stay in their gym,
  and goal feedback is written only by the entry's owner, on their own entry.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers

  alias Palee.Execution.WorkoutExecution
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Journal.GoalFeedback
  alias Palee.{Repo, TestFixtures}
  alias Palee.Workouts.WorkoutGoal

  setup do
    bypass_rls(fn ->
      {org, owner, staff} = organization_fixture()
      {member, member_context} = member_context(org)
      {_stranger, stranger_context} = member_context(org)
      {_other_org, _other_owner, other_staff} = organization_fixture()
      workout = TestFixtures.workout_fixture(owner, %{tenant_context: staff})

      Repo.insert!(%WorkoutGoal{
        organization_id: org.id,
        master_workout_id: workout.id,
        muscles: [%{"id" => "quadriceps", "role" => "primary"}],
        qualities: ["stamina"],
        source: "edited",
        taxonomy_version: 1
      })

      execution =
        Repo.insert!(%WorkoutExecution{
          user_id: member.id,
          organization_id: org.id,
          master_workout_id: workout.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        })

      %{
        org: org,
        staff: staff,
        member: member,
        member_context: member_context,
        stranger_context: stranger_context,
        other_staff: other_staff,
        execution: execution
      }
    end)
  end

  defp feedback(user_id, ctx) do
    GoalFeedback.changeset(%GoalFeedback{}, %{
      user_id: user_id,
      organization_id: ctx.org.id,
      entry_kind: "execution",
      entry_id: ctx.execution.id,
      felt_muscles: ["quadriceps"]
    })
  end

  test "workout goals are visible only inside their gym", ctx do
    assert [_goal] = RepoContext.run(ctx.staff, fn -> Repo.all(WorkoutGoal) end)
    assert [] = RepoContext.run(ctx.other_staff, fn -> Repo.all(WorkoutGoal) end)
  end

  test "feedback is written by the entry owner only", ctx do
    assert {:ok, _row} =
             RepoContext.run(ctx.member_context, fn ->
               Repo.insert(feedback(ctx.member.id, ctx))
             end)

    # Someone else cannot write a row in their own name on the member's entry,
    assert_raise Postgrex.Error, ~r/row-level security/, fn ->
      RepoContext.run(ctx.stranger_context, fn ->
        Repo.insert(feedback(ctx.stranger_context.user_id, ctx))
      end)
    end

    # nor read the member's row.
    assert [] = RepoContext.run(ctx.stranger_context, fn -> Repo.all(GoalFeedback) end)
    assert [_own] = RepoContext.run(ctx.member_context, fn -> Repo.all(GoalFeedback) end)
  end
end
