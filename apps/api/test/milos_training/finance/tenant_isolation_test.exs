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

  test "financial_summary aggregates are isolated by organization" do
    owner = TestFixtures.admin_fixture()
    first_member = TestFixtures.user_fixture(%{role: :member})
    second_member = TestFixtures.user_fixture(%{role: :member})
    first_context = tenant_context_fixture(owner, "First Summary Gym")
    second_context = tenant_context_fixture(owner, "Second Summary Gym")

    assert {:ok, first_membership} =
             Finance.upsert_membership(first_context, first_member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, second_membership} =
             Finance.upsert_membership(second_context, second_member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, _first_payment} =
             Finance.record_payment(first_context, first_membership.id, %{
               amount_cents: 15_000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, _second_payment} =
             Finance.record_payment(second_context, second_membership.id, %{
               amount_cents: 9_000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert :ok = Finance.refresh_aggregates(first_context)

    first_summary = Finance.financial_summary(first_context, %{})
    second_summary = Finance.financial_summary(second_context, %{})

    first_paid =
      first_summary.aggregates |> Enum.reduce(0, &(&1.paid_revenue_cents + &2))

    second_paid =
      second_summary.aggregates |> Enum.reduce(0, &(&1.paid_revenue_cents + &2))

    assert first_paid == 15_000
    assert second_paid == 9_000
  end

  test "invoices, memberships, and package subscriptions cannot be fetched by ID across organizations (F-05)" do
    owner = TestFixtures.admin_fixture()
    member_a = TestFixtures.user_fixture(%{role: :member})
    context_a = tenant_context_fixture(owner, "F-05 Gym A")
    context_b = tenant_context_fixture(owner, "F-05 Gym B")

    assert {:ok, package} =
             Finance.create_package(context_a, %{
               code: "f05-package",
               name: "F-05 Package",
               family: "limited",
               billing_period: "monthly",
               base_price_cents: 3_000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(context_a, member_a.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, subscription} =
             Finance.assign_package(context_a, membership.id, package.id, %{})

    assert {:ok, invoice} =
             Finance.create_invoice(context_a, membership.id, %{
               amount_cents: 3_000,
               description: "F-05 invoice",
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, %{id: fetched_invoice_id}} = Finance.get_invoice(context_a, invoice.id)
    assert fetched_invoice_id == invoice.id

    assert {:error, :not_found} = Finance.get_invoice(context_b, invoice.id)

    assert %{membership: %{id: fetched_membership_id}} =
             Finance.get_member_profile(context_a, member_a.id)

    assert fetched_membership_id == membership.id

    assert Finance.get_member_profile(context_b, member_a.id) == nil

    assert {:error, :not_found} =
             Finance.apply_credit_to_invoice(context_b, membership.id, invoice.id, %{
               amount_cents: 100,
               description: "cross-org attempt"
             })

    assert subscription.id
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
