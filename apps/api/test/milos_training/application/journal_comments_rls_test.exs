defmodule MilosTraining.Application.JournalCommentsRLSTest do
  @moduledoc """
  ADR-140 §1 Σχόλια under real Row Level Security: written only by the
  entry's owner, saved with the entry when sent with it, carrying the
  entry's gym, and read by a coach of that gym only while the entry's rung
  reaches the coach.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    CreatePR,
    GetAdminUserPRs,
    JournalComments,
    ListUserPRs,
    SetPRCoachVisibility
  }

  alias MilosTraining.Identity.UserContext
  alias MilosTraining.Organizations

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Comment Gym"})
        coach = user_fixture()
        member = user_fixture()
        other = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        %{gym: gym, coach: coach, member: member, other: other}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      other_ctx: UserContext.new(fixtures.other),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym)
    })
  end

  test "comments sent with a PR are saved with it and carry its gym", ctx do
    comment_id = Ecto.UUID.generate()

    assert {:ok, pr} =
             CreatePR.call(
               ctx.member_ctx,
               pr_params(ctx.gym, %{
                 "comments" => [
                   %{"id" => comment_id, "body" => "  Belt on  ", "tags" => ["belt"]}
                 ]
               })
             )

    assert [%{id: ^comment_id, body: "Belt on", tags: ["belt"]} = comment] = pr.comments
    assert comment.organization_id == ctx.gym.id
    assert comment.entry_kind == "pr"

    assert {:ok, [%{comments: [%{id: ^comment_id}]}]} = ListUserPRs.call(ctx.member_ctx)

    # A comment that fails validation keeps the PR from being created.
    assert {:error, %Ecto.Changeset{}} =
             CreatePR.call(
               ctx.member_ctx,
               pr_params(ctx.gym, %{"name" => "Deadlift", "comments" => [%{"body" => " "}]})
             )

    assert {:ok, [_only_the_first]} = ListUserPRs.call(ctx.member_ctx)
  end

  test "only the entry's owner comments on it", ctx do
    {:ok, pr} = CreatePR.call(ctx.member_ctx, pr_params(ctx.gym))

    assert {:error, :not_found} =
             JournalComments.save(ctx.other_ctx, Ecto.UUID.generate(), %{
               "entry_kind" => "pr",
               "entry_id" => pr.id,
               "body" => "Not mine"
             })

    {:ok, mine} =
      JournalComments.save(ctx.member_ctx, Ecto.UUID.generate(), %{
        "entry_kind" => "pr",
        "entry_id" => pr.id,
        "body" => "Mine"
      })

    # Another member cannot take over the id, nor delete it.
    assert {:error, :not_found} =
             JournalComments.save(ctx.other_ctx, mine.id, %{
               "entry_kind" => "pr",
               "entry_id" => pr.id,
               "body" => "Hijack"
             })

    assert {:error, :not_found} = JournalComments.delete(ctx.other_ctx, mine.id)
    assert :ok = JournalComments.delete(ctx.member_ctx, mine.id)
  end

  test "a coach reads comments only while the entry's rung reaches them", ctx do
    {:ok, pr} =
      CreatePR.call(
        ctx.member_ctx,
        pr_params(ctx.gym, %{
          "comments" => [%{"id" => Ecto.UUID.generate(), "body" => "Felt easy"}]
        })
      )

    assert pr.journal_visibility == "coach_can_view"

    assert {:ok, %{prs: [%{comments: [%{body: "Felt easy"}]}]}} =
             GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)

    {:ok, _sharing} = SetPRCoachVisibility.call(ctx.member_ctx, %{"coach_visibility" => false})

    assert {:ok, %{prs: []}} = GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)

    hidden =
      MilosTraining.Journal.with_context(ctx.coach_ctx, fn ->
        MilosTraining.Journal.list_comments("pr", [pr.id])
      end)

    assert hidden == []
  end

  defp pr_params(gym, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Back squat",
        "current_score" => 100,
        "unit" => "kg",
        "higher_is_better" => true,
        "beaten_on" => "2026-10-01",
        "supporting_metrics" => %{"reps" => 1},
        "organization_slug" => gym.slug
      },
      overrides
    )
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
