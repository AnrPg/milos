defmodule MilosTraining.Finance.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Finance, Organizations}
  alias MilosTraining.TestFixtures

  test "packages and member profiles are isolated by organization context" do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    first_context = tenant_context_fixture(owner, "First Finance Gym")
    second_context = tenant_context_fixture(owner, "Second Finance Gym")

    assert {:ok, first_package} =
             Finance.create_package(first_context, %{
               code: "shared-code",
               name: "Shared Package",
               family: "limited",
               billing_period: "monthly",
               base_price_cents: 5_000
             })

    assert {:ok, second_package} =
             Finance.create_package(second_context, %{
               code: "shared-code",
               name: "Shared Package",
               family: "limited",
               billing_period: "monthly",
               base_price_cents: 7_500
             })

    assert first_package.organization_id == first_context.organization_id
    assert second_package.organization_id == second_context.organization_id
    assert first_package.code == second_package.code

    assert [listed_first] = Finance.list_packages(first_context)
    assert listed_first.id == first_package.id

    assert [listed_second] = Finance.list_packages(second_context)
    assert listed_second.id == second_package.id

    assert {:ok, first_membership} =
             Finance.upsert_membership(first_context, member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, second_membership} =
             Finance.upsert_membership(second_context, member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert first_membership.organization_id == first_context.organization_id
    assert second_membership.organization_id == second_context.organization_id

    assert {:ok, _subscription} =
             Finance.assign_package(first_context, first_membership.id, first_package.id, %{})

    assert {:error, :not_found} =
             Finance.assign_package(first_context, second_membership.id, second_package.id, %{})

    assert %{membership: %{id: first_membership_id}} =
             Finance.get_member_profile(first_context, member.id)

    assert first_membership_id == first_membership.id

    assert %{membership: %{id: second_membership_id}} =
             Finance.get_member_profile(second_context, member.id)

    assert second_membership_id == second_membership.id
  end

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end
end
