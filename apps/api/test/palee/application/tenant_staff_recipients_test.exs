defmodule Palee.Application.TenantStaffRecipientsTest do
  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.TenantStaffRecipients
  alias Palee.Organizations

  setup do
    {:ok, org_a} = Organizations.create_organization(%{name: "Staff Tenant A"})
    {:ok, org_b} = Organizations.create_organization(%{name: "Staff Tenant B"})

    owner_a = user_fixture()
    coach_a = user_fixture()
    athlete_a = user_fixture(%{role: :athlete})
    owner_b = user_fixture()
    global_admin = admin_fixture()

    add_membership!(org_a, owner_a, :owner)
    add_membership!(org_a, coach_a, :coach)
    add_membership!(org_a, athlete_a, :athlete)
    add_membership!(org_b, owner_b, :owner)

    %{
      org_a: org_a,
      org_b: org_b,
      owner_a: owner_a,
      coach_a: coach_a,
      athlete_a: athlete_a,
      owner_b: owner_b,
      global_admin: global_admin
    }
  end

  test "resolves only the staff of the organization in the first source with ownership", ctx do
    ids = TenantStaffRecipients.user_ids([%{organization_id: ctx.org_a.id}])

    assert Enum.sort(ids) == Enum.sort([ctx.owner_a.id, ctx.coach_a.id])
    refute ctx.owner_b.id in ids
    refute ctx.athlete_a.id in ids
    refute ctx.global_admin.id in ids
  end

  test "skips sources without ownership and uses the next one", ctx do
    ids =
      TenantStaffRecipients.user_ids([
        nil,
        %{organization_id: nil},
        %{organization_id: ctx.org_b.id}
      ])

    assert ids == [ctx.owner_b.id]
  end

  test "accepts a single source and a bare organization id", ctx do
    assert TenantStaffRecipients.user_ids(%{organization_id: ctx.org_b.id}) == [ctx.owner_b.id]
    assert TenantStaffRecipients.user_ids(ctx.org_b.id) == [ctx.owner_b.id]
  end

  test "fails closed without ownership instead of falling back to global admins", ctx do
    assert TenantStaffRecipients.user_ids([nil, %{}, %{organization_id: nil}]) == []
    assert TenantStaffRecipients.user_ids(nil) == []
    refute ctx.global_admin.id in TenantStaffRecipients.user_ids(%{})
  end

  test "application services never fan out through global admin role lookups" do
    offenders =
      "lib/palee/application/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ "list_by_role(:admin)"))

    assert offenders == []
  end

  defp add_membership!(organization, user, role) do
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
