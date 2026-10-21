defmodule Palee.Organizations.RootReadsUnderRLSTest do
  @moduledoc """
  TD-046: root tenant table reads that production performs without a user
  session (Oban jobs, server-side fanout) or from a member's session, run here
  as the RLS-enforcing runtime role.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations

  setup do
    bypass_rls(fn ->
      {:ok, org} = Organizations.create_organization(%{name: "Root Reads Gym"})
      {:ok, other} = Organizations.create_organization(%{name: "Root Reads Other"})

      owner = user_fixture()
      coach = user_fixture()
      member = user_fixture()
      outsider = user_fixture()

      add!(org, owner, :owner)
      add!(org, coach, :coach)
      add!(org, member, :member)
      add!(other, outsider, :owner)

      %{org: org, other: other, owner: owner, coach: coach, member: member, outsider: outsider}
    end)
  end

  test "a job resolves its system tenant context without a user session", ctx do
    assert {:ok, %{organization_id: organization_id}} =
             Organizations.resolve_system_tenant_context(ctx.org.id, :job, %{})

    assert organization_id == ctx.org.id
  end

  test "staff recipients resolve for server-side callers and from a member's session", ctx do
    expected = Enum.sort([ctx.owner.id, ctx.coach.id])

    assert Enum.sort(Organizations.list_staff_user_ids(ctx.org.id)) == expected

    assert RepoContext.run(%{user_id: ctx.member.id}, fn ->
             Enum.sort(Organizations.list_staff_user_ids(ctx.org.id))
           end) == expected
  end

  test "staff lookups match the role set, not only the primary role (ADR-099)", ctx do
    member_coach = user_fixture()
    bypass_rls(fn -> add!(ctx.org, member_coach, :member, [:member, :coach]) end)

    assert member_coach.id in Organizations.list_staff_user_ids(ctx.org.id)

    assert member_coach.id in Enum.map(Organizations.list_staff(ctx.org.id), & &1.user_id)
  end

  test "role facts of other members resolve from a coach's session (TD-092)", ctx do
    RepoContext.run(%{user_id: ctx.coach.id}, fn ->
      assert Organizations.member_roles(ctx.org.id, ctx.owner.id) == [:owner]
      assert Organizations.list_manager_user_ids(ctx.org.id) == [ctx.owner.id]
      assert %{roles: ["member"]} = Organizations.membership_summary(ctx.org.id, ctx.member.id)
    end)
  end

  test "the role facts function refuses a session outside the organization", ctx do
    %{rows: rows} =
      RepoContext.run(%{user_id: ctx.outsider.id, organization_id: ctx.other.id}, fn ->
        Repo.query!("SELECT * FROM palee_organization_member_roles($1::uuid, NULL, NULL)", [
          Ecto.UUID.dump!(ctx.org.id)
        ])
      end)

    assert rows == []
  end

  test "co-members are visible to a member of the organization", ctx do
    ids = Organizations.list_active_membership_user_ids(ctx.org.id)
    assert Enum.sort(ids) == Enum.sort([ctx.owner.id, ctx.coach.id, ctx.member.id])
  end

  test "the membership lookup function refuses a session outside the organization", ctx do
    %{rows: rows} =
      RepoContext.run(%{user_id: ctx.outsider.id, organization_id: ctx.other.id}, fn ->
        Repo.query!("SELECT palee_organization_user_ids($1::uuid, NULL)", [
          Ecto.UUID.dump!(ctx.org.id)
        ])
      end)

    assert rows == []
  end

  test "an organization row stays invisible to an unrelated session", ctx do
    assert RepoContext.run(%{user_id: ctx.outsider.id, organization_id: ctx.other.id}, fn ->
             Repo.get(Palee.Organizations.Organization, ctx.org.id)
           end) == nil
  end

  defp add!(organization, user, role, roles \\ nil) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: roles || [role],
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
