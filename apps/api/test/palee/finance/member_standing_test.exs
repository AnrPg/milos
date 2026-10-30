defmodule Palee.Finance.MemberStandingTest do
  # ADR-274: charges per subscription period, the worked-out status, values
  # staff set by hand and «Οφειλές».
  use Palee.DataCase

  alias Palee.{Finance, Organizations}
  alias Palee.TestFixtures

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

  setup do
    owner = TestFixtures.admin_fixture()
    context = tenant_context_fixture(owner, "Standing #{System.unique_integer([:positive])}")

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    {:ok, package} =
      Finance.create_package(%{
        name: "Monthly #{System.unique_integer([:positive])}",
        package_type: "membership",
        billing_period: "monthly",
        base_price_cents: 5000,
        fields: %{"terms.auto_renew" => true}
      })

    user = TestFixtures.user_fixture(%{role: :member})

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    %{owner: owner, context: context, package: package, user: user, membership: membership}
  end

  defp profile(user), do: Finance.get_member_profile(user.id)

  test "a newly profiled member without a package shows «Χωρίς πακέτο»", %{user: user} do
    assert profile(user).membership.status_shown == "no_package"
  end

  test "assigning a package charges its first period at once", %{
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    assert subscription.charges_from == gym_today()

    assert [charge] = profile(user).invoices
    assert charge.invoice_type == "subscription"
    assert charge.status == "issued"
    assert charge.total_cents == 5000
    assert charge.balance_due_cents == 5000
    assert charge.membership_package_subscription_id == subscription.id

    assert profile(user).membership.status_shown == "unpaid"
    assert Finance.membership_outstanding_balance_cents(membership.id) == 5000

    # Paying it makes them active.
    assert {:ok, _payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: charge.id,
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert profile(user).membership.status_shown == "active"
  end

  test "a desk payment recorded for the package before its charge counts against it",
       %{user: user, membership: membership, package: package} do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{charge_now: false})
    _ = user

    {:ok, _paid} =
      Finance.create_invoice(membership.id, %{
        "membership_package_subscription_id" => subscription.id,
        "amount_cents" => 500,
        "status" => "paid",
        "issue_date" => gym_today()
      })

    assert {:ok, [charge]} = Finance.charge_subscription_now(subscription.id)
    assert charge.total_cents == 4500
    assert {:ok, []} = Finance.charge_subscription_now(subscription.id)
  end

  test "the hourly run charges each new period once, and only while renewal is on",
       %{context: context, user: user, membership: membership, package: package} do
    starts_on = Date.shift(gym_today(), month: -2)

    {:ok, subscription} =
      Finance.assign_package(membership.id, package.id, %{starts_on: starts_on, charge_now: false})

    charges = Finance.charge_due_subscriptions(gym_today())
    assert length(charges) == 3
    assert Enum.map(charges, & &1.invoice_type) == ["subscription", "renewal", "renewal"]
    assert Finance.charge_due_subscriptions(gym_today()) == []

    # Overdue beyond the grace days: «Ληξιπρόθεσμο».
    assert profile(user).membership.status_shown == "overdue"

    {:ok, _} =
      Finance.set_subscription_auto_renew(context, user.id, subscription.id, false, "staff")

    next_month = Date.shift(gym_today(), month: 1)
    assert Finance.charge_due_subscriptions(next_month) == []
  end

  test "a status set by hand is kept, traced, and lapses when the automatic value moves on",
       %{user: user, owner: owner, membership: membership, package: package} do
    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    assert profile(user).membership.status_shown == "unpaid"

    assert {:ok, override} =
             Finance.set_value_override(user.id, "status", %{
               value: "active",
               reason: "Pays on Friday",
               actor_id: owner.id
             })

    assert override.computed_value == "unpaid"
    assert override.value == "active"
    assert override.set_by_id == owner.id
    assert profile(user).membership.status_shown == "active"

    # Paying changes the automatic value: the override ends by itself.
    [charge] = profile(user).invoices

    {:ok, _payment} =
      Finance.record_payment(membership.id, %{
        finance_invoice_id: charge.id,
        amount_cents: 5000,
        payment_method: "cash",
        payment_status: "paid"
      })

    assert [%{end_reason: "lapsed", ended_at: %DateTime{}}] =
             Finance.list_value_overrides(user.id)

    assert profile(user).membership.status_shown == "active"
  end

  test "resetting puts the automatic value back and keeps the history",
       %{user: user, membership: membership, package: package} do
    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    {:ok, _} = Finance.set_value_override(user.id, "status", %{value: "paused"})
    assert profile(user).membership.status == "paused"

    {:ok, _} = Finance.set_value_override(user.id, "status", %{value: "comped"})
    assert {:ok, %{end_reason: "reset"}} = Finance.reset_value_override(user.id, "status", %{})
    assert profile(user).membership.status_shown == "unpaid"
    assert profile(user).membership.status == "active"

    assert [%{value: "comped", end_reason: "reset"}, %{value: "paused", end_reason: "replaced"}] =
             Finance.list_value_overrides(user.id)

    assert {:error, :override_not_found} = Finance.reset_value_override(user.id, "status", %{})

    assert {:error, :invalid_override_value} =
             Finance.set_value_override(user.id, "status", %{value: "unpaid"})
  end

  test "a subscription's last day set by hand ends it there until reset",
       %{user: user, membership: membership, package: package} do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    last_day = Date.add(gym_today(), 10)

    assert {:ok, override} =
             Finance.set_value_override(user.id, "ends_on", %{
               value: Date.to_iso8601(last_day),
               subscription_id: subscription.id
             })

    assert override.computed_value == nil
    assert [%{ends_on: ^last_day}] = profile(user).package_subscriptions

    assert {:ok, _} =
             Finance.reset_value_override(user.id, "ends_on", %{subscription_id: subscription.id})

    assert [%{ends_on: nil}] = profile(user).package_subscriptions
  end

  test "«Οφειλές» lists one row per person with what they owe and since when",
       %{user: user, membership: membership, package: package} do
    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})

    %{open_charges: [row]} = Finance.operational_queues(%{})
    assert row.user_id == user.id
    assert row.membership_id == membership.id
    assert row.balance_due_cents == 5000
    assert row.oldest_due_on == gym_today()
    assert row.state == "unpaid"
  end

  test "an imported member is billed from the next period", %{
    membership: membership,
    package: package
  } do
    {:ok, subscription} =
      Finance.assign_package(membership.id, package.id, %{
        starts_on: Date.add(gym_today(), -3),
        charges_from: "next_period",
        charge_now: false
      })

    assert subscription.charges_from == Date.shift(Date.add(gym_today(), -3), month: 1)
    assert Finance.charge_due_subscriptions(gym_today()) == []
  end

  test "a free package or a corporate seat is never charged", %{
    user: user,
    membership: membership
  } do
    {:ok, free} =
      Finance.create_package(%{
        name: "Free #{System.unique_integer([:positive])}",
        package_type: "membership",
        base_price_cents: 0
      })

    {:ok, subscription} = Finance.assign_package(membership.id, free.id, %{})
    assert subscription.charges_from == nil
    assert profile(user).invoices == []
    assert profile(user).membership.status_shown == "comped"
  end

  test "money taken at the desk for the package settles its open charge", %{
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    [charge] = profile(user).invoices

    assert {:ok, received} =
             Finance.receive_payment(membership.id, %{
               "idempotency_key" => Ecto.UUID.generate(),
               "membership_package_subscription_id" => subscription.id,
               "amount_cents" => 500,
               "payment_method" => "cash"
             })

    assert received.invoice.id == charge.id
    assert [%{balance_due_cents: 4500}] = profile(user).invoices
    assert profile(user).membership.status_shown == "unpaid"
  end
end
