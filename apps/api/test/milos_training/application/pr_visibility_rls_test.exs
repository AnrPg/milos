defmodule MilosTraining.Application.PRVisibilityRLSTest do
  @moduledoc """
  ADR-129 / TD-077 under real Row Level Security: who may read a member's
  Pantheon PRs. Fixtures are seeded as the superuser; every assertion runs as
  the RLS-enforcing runtime role through the real application services.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    CreatePR,
    GetAdminUserPRs,
    GetPRHistory,
    GetPRSharing,
    GrantPRAccess,
    ListPRsSharedWithMe,
    ListUserPRs,
    RevokePRAccess,
    SetPRCoachVisibility,
    SharePR,
    UpdatePR
  }

  alias MilosTraining.Identity.UserContext
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.{Organizations, Pantheon}

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym_a} = Organizations.create_organization(%{name: "PR Gym A"})
        {:ok, gym_b} = Organizations.create_organization(%{name: "PR Gym B"})

        owner = user_fixture()
        admin = user_fixture()
        coach = user_fixture()
        coach_b = user_fixture()
        member = user_fixture()
        friend = user_fixture()

        add!(gym_a, owner, :owner)
        add!(gym_a, admin, :admin)
        add!(gym_a, coach, :coach)
        member_a = add!(gym_a, member, :member)
        add!(gym_b, coach_b, :coach)
        add!(gym_b, member, :athlete)
        add!(gym_b, coach, :member)

        %{
          gym_a: gym_a,
          gym_b: gym_b,
          owner: owner,
          admin: admin,
          coach: coach,
          coach_b: coach_b,
          member: member,
          member_a: member_a,
          friend: friend,
          owner_ctx: tenant!(owner, gym_a),
          admin_ctx: tenant!(admin, gym_a),
          coach_ctx: tenant!(coach, gym_a),
          coach_b_ctx: tenant!(coach_b, gym_b),
          coach_in_b_ctx: tenant!(coach, gym_b)
        }
      end)

    member_ctx = UserContext.new(fixtures.member)
    {:ok, pr_a} = CreatePR.call(member_ctx, pr_params("Back squat", fixtures.gym_a.slug))
    {:ok, pr_b} = CreatePR.call(member_ctx, pr_params("Snatch", fixtures.gym_b.slug))
    {:ok, personal} = CreatePR.call(member_ctx, pr_params("Marathon", nil))

    {:ok, _improved} =
      UpdatePR.call(member_ctx, pr_a.id, %{"current_score" => 130, "beaten_on" => today()})

    Map.merge(fixtures, %{member_ctx: member_ctx, pr_a: pr_a, pr_b: pr_b, personal: personal})
  end

  test "creation records gym provenance only for the member's own active gyms", ctx do
    assert ctx.pr_a.organization_id == ctx.gym_a.id
    assert ctx.pr_b.organization_id == ctx.gym_b.id
    assert is_nil(ctx.personal.organization_id)

    {:ok, foreign} = bypass_rls(fn -> Organizations.create_organization(%{name: "Foreign"}) end)

    assert {:error, :pr_organization_unavailable} =
             CreatePR.call(ctx.member_ctx, pr_params("Clean", foreign.slug))
  end

  test "a coach sees the gym's PRs of its members, with history", ctx do
    assert {:ok, %{visibility: "coach", prs: [pr]}} =
             GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)

    assert pr.id == ctx.pr_a.id
    assert pr.current_score == 130.0
    assert [%{score: 120.0}] = pr.history
  end

  test "a coach of gym A sees neither the member's gym B PRs nor personal PRs", ctx do
    visible_ids =
      Pantheon.with_tenant_context(ctx.coach_ctx, fn ->
        ctx.member.id |> Pantheon.list_records() |> Enum.map(& &1.id)
      end)

    assert visible_ids == [ctx.pr_a.id]

    # Even when the same person is scoped into gym B (as a plain member there),
    # gym A's PRs are not visible: visibility follows the session's tenant.
    assert Pantheon.with_tenant_context(ctx.coach_in_b_ctx, fn ->
             Pantheon.list_records(ctx.member.id)
           end) == []

    assert {:ok, %{visibility: "coach", prs: [%{id: gym_b_id}]}} =
             GetAdminUserPRs.call(ctx.coach_b_ctx, ctx.member.id)

    assert gym_b_id == ctx.pr_b.id
  end

  test "owners and admins who are not coaches see nothing", ctx do
    for staff_ctx <- [ctx.owner_ctx, ctx.admin_ctx] do
      assert {:ok, %{visibility: "coach_role_required", prs: []}} =
               GetAdminUserPRs.call(staff_ctx, ctx.member.id)

      # The database agrees: no policy admits a non-coach staff session.
      assert Pantheon.with_tenant_context(staff_ctx, fn ->
               {Pantheon.list_records(ctx.member.id), Pantheon.list_record_history(ctx.pr_a.id)}
             end) == {[], []}
    end
  end

  # TD-091: the multi-role seam swap (`'coach' = ANY(om.roles)`, migration
  # 20261015100000). An owner or admin whose role set includes coach passes
  # the seam in both the service and the database; coach client scope
  # (ADR-100) never narrows PR visibility.
  test "an owner or admin who also coaches sees the gym's PRs", ctx do
    owner_coach = user_fixture()
    admin_coach = user_fixture()

    bypass_rls(fn ->
      add_roles!(ctx.gym_a, owner_coach, [:owner, :coach])
      add_roles!(ctx.gym_a, admin_coach, [:admin, :coach])
    end)

    for user <- [owner_coach, admin_coach] do
      staff_ctx = tenant!(user, ctx.gym_a)
      assert Organizations.acting_user_coaches?(staff_ctx)

      assert {:ok, %{visibility: "coach", prs: [%{id: pr_id}]}} =
               GetAdminUserPRs.call(staff_ctx, ctx.member.id)

      assert pr_id == ctx.pr_a.id

      assert [%{id: ^pr_id}] =
               Pantheon.with_tenant_context(staff_ctx, fn ->
                 Pantheon.list_organization_records(ctx.member.id, ctx.gym_a.id)
               end)
    end
  end

  test "coach client scope does not narrow PR visibility", ctx do
    # The gym-A coach has `coach_scope: :own` and no coaching relationship
    # with the member, yet reads the member's gym-A PR.
    assert %{coach_scope: "own"} =
             bypass_rls(fn -> Organizations.membership_summary(ctx.gym_a.id, ctx.coach.id) end)

    assert {:ok, %{visibility: "coach", prs: [_pr]}} =
             GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)
  end

  test "opting out hides PRs from coaches but not from explicit grantees", ctx do
    assert {:ok, %{coach_visibility: true}} = GetPRSharing.call(ctx.member_ctx)
    {:ok, _grant} = GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.friend.id})

    assert {:ok, %{coach_visibility: false}} =
             SetPRCoachVisibility.call(ctx.member_ctx, %{"coach_visibility" => false})

    assert {:ok, %{prs: []}} = GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)
    assert {:ok, %{prs: []}} = GetAdminUserPRs.call(ctx.coach_b_ctx, ctx.member.id)

    assert {:ok, %{shared: [%{prs: prs}]}} = ListPRsSharedWithMe.call(UserContext.new(ctx.friend))
    assert length(prs) == 3

    assert {:ok, %{coach_visibility: true}} =
             SetPRCoachVisibility.call(ctx.member_ctx, %{"coach_visibility" => true})

    assert {:ok, %{prs: [_pr]}} = GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)
  end

  test "the opt-out is owner-only and validated", ctx do
    assert {:error, :bad_request} =
             SetPRCoachVisibility.call(ctx.member_ctx, %{"coach_visibility" => "nope"})

    # A coach cannot read or write the member's preference row.
    assert RepoContext.run(ctx.coach_ctx, fn ->
             Repo.query!("SELECT count(*) FROM user_pr_sharing_preferences").rows
           end) == [[0]]
  end

  test "a grantee sees all of the owner's PRs regardless of gym, read-only", ctx do
    friend_ctx = UserContext.new(ctx.friend)

    assert {:ok, grant} =
             GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.friend.id})

    assert grant.grantee.id == ctx.friend.id

    # Idempotent: granting again returns the same active grant.
    assert {:ok, %{id: same_id}} =
             GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.friend.id})

    assert same_id == grant.id

    assert {:ok, %{shared: [shared]}} = ListPRsSharedWithMe.call(friend_ctx)
    assert shared.owner.id == ctx.member.id

    assert Enum.sort(Enum.map(shared.prs, & &1.id)) ==
             Enum.sort([ctx.pr_a.id, ctx.pr_b.id, ctx.personal.id])

    assert Enum.find(shared.prs, &(&1.id == ctx.pr_a.id)).history |> length() == 1

    # Read-only: owner-scoped operations stay closed to the grantee.
    assert {:error, :not_found} =
             UpdatePR.call(friend_ctx, ctx.pr_a.id, %{"current_score" => 1})

    assert {:error, :not_found} = GetPRHistory.call(friend_ctx, ctx.pr_a.id)
    assert {:error, :not_found} = SharePR.call(friend_ctx, ctx.pr_a.id)
    assert {:ok, []} = ListUserPRs.call(friend_ctx, [])

    # The grantee sees the grant naming them, but not the owner's other grants.
    {:ok, _other} = GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.coach.id})

    assert RepoContext.run(friend_ctx, fn ->
             Repo.query!("SELECT count(*) FROM user_pr_share_grants").rows
           end) == [[1]]
  end

  test "a revoked grant hides the owner's PRs again", ctx do
    friend_ctx = UserContext.new(ctx.friend)
    {:ok, grant} = GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.friend.id})

    assert :ok = RevokePRAccess.call(ctx.member_ctx, grant.id)
    assert {:error, :not_found} = RevokePRAccess.call(ctx.member_ctx, grant.id)
    assert {:ok, %{shared: []}} = ListPRsSharedWithMe.call(friend_ctx)
    assert {:ok, %{grants: []}} = GetPRSharing.call(ctx.member_ctx)

    assert Pantheon.with_user_context(friend_ctx, fn ->
             {Pantheon.list_records(ctx.member.id), Pantheon.list_record_history(ctx.pr_a.id)}
           end) == {[], []}

    # Only the owner can revoke.
    {:ok, regrant} = GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.friend.id})
    assert {:error, :not_found} = RevokePRAccess.call(friend_ctx, regrant.id)
  end

  test "sharing with yourself or an unknown account is refused", ctx do
    assert {:error, :cannot_share_prs_with_self} =
             GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => ctx.member.id})

    assert {:error, :not_found} =
             GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => Ecto.UUID.generate()})

    assert {:error, :bad_request} =
             GrantPRAccess.call(ctx.member_ctx, %{"grantee_user_id" => "not-a-uuid"})
  end

  test "an inactive membership hides the member's gym PRs from its coaches", ctx do
    bypass_rls(fn ->
      {:ok, _suspended} =
        Organizations.set_membership_status(ctx.owner_ctx, ctx.member_a.id, :suspended)
    end)

    assert {:ok, %{prs: []}} = GetAdminUserPRs.call(ctx.coach_ctx, ctx.member.id)
  end

  test "single-PR sharing keeps working for the owner", ctx do
    assert {:ok, %{message: message}} = SharePR.call(ctx.member_ctx, ctx.pr_a.id)
    assert message =~ "Back squat"

    assert {:ok, prs} = ListUserPRs.call(ctx.member_ctx, [])
    assert length(prs) == 3
  end

  defp pr_params(name, slug) do
    %{
      "name" => name,
      "current_score" => 120,
      "unit" => "kg",
      "beaten_on" => today(),
      "supporting_metrics" => %{"reps" => 1},
      "organization_slug" => slug
    }
  end

  defp today, do: Date.to_iso8601(Date.utc_today())

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

  defp add_roles!(organization, user, roles) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        roles: roles,
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
