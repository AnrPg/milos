defmodule MilosTraining.Organizations.RootReadsUnderRLSTest do
  @moduledoc """
  TD-046: root tenant table reads that production performs without a user
  session (Oban jobs, server-side fanout) or from a member's session, run here
  as the RLS-enforcing runtime role.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations

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

  test "co-members are visible to a member of the organization", ctx do
    ids = Organizations.list_active_membership_user_ids(ctx.org.id)
    assert Enum.sort(ids) == Enum.sort([ctx.owner.id, ctx.coach.id, ctx.member.id])
  end

  test "the membership lookup function refuses a session outside the organization", ctx do
    %{rows: rows} =
      RepoContext.run(%{user_id: ctx.outsider.id, organization_id: ctx.other.id}, fn ->
        Repo.query!("SELECT milos_organization_user_ids($1::uuid, NULL)", [
          Ecto.UUID.dump!(ctx.org.id)
        ])
      end)

    assert rows == []
  end

  test "an organization row stays invisible to an unrelated session", ctx do
    assert RepoContext.run(%{user_id: ctx.outsider.id, organization_id: ctx.other.id}, fn ->
             Repo.get(MilosTraining.Organizations.Organization, ctx.org.id)
           end) == nil
  end

  defp add!(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
