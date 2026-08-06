defmodule MilosTraining.Organizations.SetMembershipStatusTest do
  @moduledoc """
  F-11: proves a membership can actually be de-authorized, and that the next
  tenant-scoped request is rejected as a result.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.OrganizationStore
  alias MilosTraining.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})

    {:ok, organization} = Organizations.create_organization(%{name: "Suspend Gym"})

    {:ok, _owner_membership} = add_membership(organization, owner, :owner)
    {:ok, member_membership} = add_membership(organization, member, :member)

    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok,
     owner: owner,
     member: member,
     organization: organization,
     owner_context: owner_context,
     member_membership: member_membership}
  end

  test "revoking a membership rejects that account's next tenant-scoped request", %{
    member: member,
    organization: organization,
    owner_context: owner_context,
    member_membership: member_membership
  } do
    # The member can resolve a tenant context while active.
    assert {:ok, _context} = Organizations.resolve_tenant_context(member, organization.slug)

    assert {:ok, updated} =
             Organizations.set_membership_status(owner_context, member_membership.id, :revoked)

    assert updated.status == :revoked

    # TenantAuthorization.build/4 refuses any non-active membership, so no
    # further change is needed for the revocation to bite.
    assert {:error, :inactive_membership} =
             Organizations.resolve_tenant_context(member, organization.slug)
  end

  test "suspending and reinstating round-trips", %{
    member: member,
    organization: organization,
    owner_context: owner_context,
    member_membership: member_membership
  } do
    assert {:ok, _} =
             Organizations.set_membership_status(owner_context, member_membership.id, :suspended)

    assert {:error, :inactive_membership} =
             Organizations.resolve_tenant_context(member, organization.slug)

    assert {:ok, _} =
             Organizations.set_membership_status(owner_context, member_membership.id, "active")

    assert {:ok, _context} = Organizations.resolve_tenant_context(member, organization.slug)
  end

  test "an account cannot change its own membership status", %{
    owner: owner,
    organization: organization,
    owner_context: owner_context
  } do
    own_membership = OrganizationStore.get_membership(organization.id, owner.id)

    assert {:error, :cannot_change_own_membership} =
             Organizations.set_membership_status(owner_context, own_membership.id, :revoked)
  end

  test "an admin cannot revoke a more privileged membership", %{
    organization: organization,
    member: member
  } do
    admin = TestFixtures.admin_fixture()
    {:ok, _} = add_membership(organization, admin, :admin)
    {:ok, admin_context} = Organizations.resolve_tenant_context(admin, organization.slug)

    owner_membership =
      organization.id
      |> OrganizationStore.list_organization_memberships()
      |> Enum.find(&(&1.role == :owner))

    assert {:error, :role_ceiling_exceeded} =
             Organizations.set_membership_status(admin_context, owner_membership.id, :revoked)

    # ...but may act on a less privileged one.
    member_membership = OrganizationStore.get_membership(organization.id, member.id)

    assert {:ok, _} =
             Organizations.set_membership_status(admin_context, member_membership.id, :suspended)
  end

  test "a coach cannot change membership status at all", %{
    organization: organization,
    member_membership: member_membership
  } do
    coach = TestFixtures.user_fixture(%{role: :member})
    {:ok, _} = add_membership(organization, coach, :coach)
    {:ok, coach_context} = Organizations.resolve_tenant_context(coach, organization.slug)

    assert {:error, :forbidden} =
             Organizations.set_membership_status(coach_context, member_membership.id, :revoked)
  end

  test "an unknown status is rejected", %{
    owner_context: owner_context,
    member_membership: member_membership
  } do
    assert {:error, [status: "is invalid"]} =
             Organizations.set_membership_status(owner_context, member_membership.id, "deleted")
  end

  test "a membership from another organization is not reachable", %{owner_context: owner_context} do
    other_owner = TestFixtures.admin_fixture()
    {:ok, other_org} = Organizations.create_organization(%{name: "Other Suspend Gym"})
    {:ok, other_membership} = add_membership(other_org, other_owner, :owner)

    assert {:error, :not_found} =
             Organizations.set_membership_status(owner_context, other_membership.id, :revoked)
  end

  defp add_membership(organization, user, role) do
    Organizations.add_membership(%{
      organization_id: organization.id,
      user_id: user.id,
      role: role,
      status: :active,
      joined_at: DateTime.utc_now()
    })
  end
end
