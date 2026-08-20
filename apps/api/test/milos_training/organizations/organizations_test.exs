defmodule MilosTraining.OrganizationsTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Organizations, Repo}
  alias MilosTraining.Organizations.OrganizationSetting
  alias MilosTraining.Organizations.TenantContext

  import MilosTraining.TestFixtures

  setup do
    owner = user_fixture()
    member = user_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "North Star Strength"})

    {:ok, owner_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} =
      Organizations.resolve_tenant_context(owner, organization.slug, %{transport: :test})

    %{
      owner: owner,
      member: member,
      organization: organization,
      owner_membership: owner_membership,
      context: context
    }
  end

  test "queries organizations and memberships through the public API", context do
    assert Organizations.get_by_id(context.organization.id).slug == context.organization.slug
    assert Organizations.get_by_slug(context.organization.slug).id == context.organization.id

    assert Enum.any?(Organizations.list_memberships(context.owner.id), fn entry ->
             entry.organization.id == context.organization.id and
               entry.membership.role == :owner
           end)

    assert %TenantContext{membership_id: membership_id} = context.context
    assert membership_id == context.owner_membership.id
  end

  test "creates tenant settings with a brand fallback" do
    assert {:ok, organization} = Organizations.create_organization(%{name: "Brand Fallback Gym"})

    assert %{brand_name: "Brand Fallback Gym"} =
             Repo.get_by(OrganizationSetting, organization_id: organization.id)
  end

  test "issues, inspects, revokes, and redeems opaque invitations", context do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, %{token: token, invitation: invitation}} =
             Organizations.issue_invitation(
               context.context,
               %{role: :member, lifetime_seconds: 3_600},
               now
             )

    refute Map.has_key?(Map.from_struct(invitation), :token)

    assert {:ok, inspected} = Organizations.inspect_invitation(token, now)
    assert inspected.organization.id == context.organization.id
    assert inspected.role == :member

    assert {:ok, %{membership: membership}} =
             Organizations.redeem_invitation(token, context.member.id, now)

    assert membership.user_id == context.member.id

    assert {:error, :invalid_invitation} =
             Organizations.redeem_invitation(token, user_fixture().id, now)

    assert {:ok, %{token: second_token, invitation: second_invitation}} =
             Organizations.issue_invitation(context.context, %{role: :athlete}, now)

    assert {:ok, _revoked} =
             Organizations.revoke_invitation(context.context, second_invitation.id, now)

    assert {:error, :invalid_invitation} = Organizations.inspect_invitation(second_token, now)
  end

  test "only owner and admin memberships may manage invitations", context do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: context.organization.id,
        user_id: context.member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    member_context = %TenantContext{
      organization: context.organization,
      membership: membership,
      account: context.member,
      organization_id: context.organization.id,
      membership_id: membership.id,
      user_id: context.member.id,
      role: :member,
      request_metadata: %{}
    }

    assert {:error, :forbidden} =
             Organizations.issue_invitation(member_context, %{role: :member})

    assert {:error, :forbidden} =
             Organizations.issue_invitation(%{member_context | role: :coach}, %{role: :member})
  end

  test "an admin cannot invite someone to owner, but can invite up to admin", context do
    {:ok, admin_membership} =
      Organizations.add_membership(%{
        organization_id: context.organization.id,
        user_id: context.member.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    admin_context = %TenantContext{
      organization: context.organization,
      membership: admin_membership,
      account: context.member,
      organization_id: context.organization.id,
      membership_id: admin_membership.id,
      user_id: context.member.id,
      role: :admin,
      request_metadata: %{}
    }

    assert {:error, :role_ceiling_exceeded} =
             Organizations.issue_invitation(admin_context, %{role: :owner})

    assert {:ok, %{invitation: invitation}} =
             Organizations.issue_invitation(admin_context, %{role: :admin})

    assert invitation.role == :admin
  end

  test "an owner can invite a peer owner" do
    owner = user_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Owner Ceiling Gym"})

    {:ok, owner_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    assert context.membership_id == owner_membership.id

    assert {:ok, %{invitation: invitation}} =
             Organizations.issue_invitation(context, %{role: :owner})

    assert invitation.role == :owner
  end

  test "concurrent redemption consumes an invitation exactly once", context do
    other_member = user_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, %{token: token}} =
      Organizations.issue_invitation(context.context, %{role: :member}, now)

    tasks =
      [context.member.id, other_member.id]
      |> Enum.map(fn user_id ->
        Task.async(fn -> Organizations.redeem_invitation(token, user_id, now) end)
      end)

    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert 1 == Enum.count(results, &match?({:ok, _redemption}, &1))
    assert 1 == Enum.count(results, &match?({:error, :invalid_invitation}, &1))
  end

  test "legacy organization creation is idempotent" do
    assert {:ok, first} = Organizations.ensure_legacy_organization_for_migration()
    assert {:ok, second} = Organizations.ensure_legacy_organization_for_migration()
    assert first.id == second.id
    assert first.slug == "legacy-milos-training"
    assert first.name == "Milos Training"
  end
end
