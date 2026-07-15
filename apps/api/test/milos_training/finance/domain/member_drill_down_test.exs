defmodule MilosTraining.Finance.Domain.MemberDrillDownTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.MemberDrillDown

  @today ~D[2026-06-13]

  test "builds an active member drill-down with status, timeline, outstanding items, and actions" do
    user = %{id: "user-1", nickname: "maria", role: :member}

    profile = %{
      membership: %{
        id: "membership-1",
        user_id: "user-1",
        user_type_snapshot: "member",
        status: "expiring",
        signup_source: "direct",
        starts_on: ~D[2026-01-01],
        expires_on: ~D[2026-06-20],
        notes: "Prefers bank transfer",
        entitlement_status: "grace",
        entitlement_source: "open_invoice",
        entitlement_expires_on: ~D[2026-06-20]
      },
      active_package_subscription: %{
        id: "subscription-1",
        status: "active",
        package_code_snapshot: "unlimited_monthly",
        package_family_snapshot: "unlimited",
        billing_period_snapshot: "monthly",
        price_cents_snapshot: 9000,
        starts_on: ~D[2026-06-01],
        ends_on: nil
      },
      package_subscriptions: [],
      invoices: [
        %{
          id: "invoice-1",
          invoice_number: "INV-1",
          invoice_type: "renewal",
          status: "issued",
          due_date: ~D[2026-06-10],
          total_cents: 9000,
          paid_cents: 0,
          credit_applied_cents: 0,
          balance_due_cents: 9000,
          inserted_at: ~U[2026-06-01 09:00:00Z]
        }
      ],
      payments: [
        %{
          id: "payment-1",
          payment_status: "paid",
          amount_cents: 9000,
          net_amount_cents: 9000,
          paid_on: ~D[2026-05-01],
          inserted_at: ~U[2026-05-01 10:00:00Z]
        }
      ],
      payment_reversals: [],
      promotion_redemptions: [],
      credit_ledger_entries: [
        %{
          id: "credit-1",
          entry_type: "grant",
          source_type: "manual_credit",
          amount_cents: 1500,
          description: "Goodwill",
          occurred_at: ~U[2026-05-15 12:00:00Z],
          occurred_on: ~D[2026-05-15]
        }
      ],
      credit_balance: 1500,
      entitlement: %{
        status: "grace",
        source: "open_invoice",
        expires_on: ~D[2026-06-20],
        open_invoice_count: 1,
        overdue_invoice_count: 1,
        credit_balance_cents: 1500
      }
    }

    drill_down = MemberDrillDown.build(user, profile, @today)

    assert drill_down.identity == %{
             user_id: "user-1",
             nickname: "maria",
             role: "member",
             user_type: "member"
           }

    assert drill_down.current_status.state == "expiring"
    assert drill_down.current_status.entitlement_status == "grace"
    assert drill_down.current_status.days_until_expiry == 7
    assert drill_down.current_status.urgency == "urgent"

    assert drill_down.package_relationship.status == "active"
    assert drill_down.package_relationship.current_package.code == "unlimited_monthly"

    assert [%{type: "overdue_invoice", severity: "high"} | _] = drill_down.outstanding_items

    assert Enum.map(drill_down.financial_timeline, & &1.type) == [
             "invoice",
             "credit",
             "payment"
           ]

    actions = Map.new(drill_down.actions, &{&1.key, &1})
    assert actions["update_membership"].available
    assert actions["renew_membership"].available
    assert actions["cancel_membership"].available
    assert actions["record_payment"].available
  end

  test "builds an unmanaged profile without requiring source finance facts" do
    drill_down =
      MemberDrillDown.build(
        %{id: "user-2", nickname: "nikos", role: :member},
        %{membership: nil, package_subscriptions: [], payments: []},
        @today
      )

    assert drill_down.current_status.state == "unmanaged"
    assert drill_down.package_relationship.status == "unassigned"

    assert [%{type: "membership_profile_missing", severity: "medium"}] =
             drill_down.outstanding_items

    actions = Map.new(drill_down.actions, &{&1.key, &1})
    assert actions["update_membership"].available
    refute actions["assign_package"].available
    assert actions["assign_package"].reason == "membership_profile_required"
  end
end
