defmodule MilosTraining.FinanceTest do
  use MilosTraining.DataCase

  alias MilosTraining.Finance
  alias MilosTraining.TestFixtures

  test "creates a membership package and assigns it to a membership profile" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "Unlimited Monthly",
               name: "Unlimited Monthly",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 9000,
               tags: ["crossfit"],
               params: %{visits_per_week: "unlimited"}
             })

    assert package.code == "unlimited_monthly"

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert {:ok, subscription} =
             Finance.assign_package(membership.id, package.id, %{
               starts_on: Date.utc_today()
             })

    assert subscription.package_code_snapshot == "unlimited_monthly"
    assert subscription.package_family_snapshot == "unlimited"

    profile = Finance.get_member_profile(user.id)
    assert profile.membership.status == "active"
    assert profile.membership.entitlement_status == "active"
    assert [^subscription] = profile.package_subscriptions
    assert Finance.get_package(package.id).code == "unlimited_monthly"
  end

  test "member profile reads do not refresh entitlement snapshots" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert membership.entitlement_updated_at
    before_profile = Finance.get_member_profile(user.id)
    Process.sleep(2)
    after_profile = Finance.get_member_profile(user.id)

    assert before_profile.membership.updated_at == after_profile.membership.updated_at

    assert before_profile.membership.entitlement_updated_at ==
             after_profile.membership.entitlement_updated_at
  end

  test "rejects inactive packages and ignores future or expired subscriptions for entitlement and renewal" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, inactive_package} =
             Finance.create_package(%{
               code: "inactive_package",
               name: "Inactive Package",
               family: "unlimited",
               billing_period: "monthly",
               active: false
             })

    assert {:ok, active_package} =
             Finance.create_package(%{
               code: "dated_package",
               name: "Dated Package",
               family: "unlimited",
               billing_period: "monthly"
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 60)
             })

    assert {:error, :package_inactive} =
             Finance.assign_package(membership.id, inactive_package.id, %{})

    assert {:ok, future_subscription} =
             Finance.assign_package(membership.id, active_package.id, %{
               starts_on: Date.add(Date.utc_today(), 10),
               ends_on: Date.add(Date.utc_today(), 40)
             })

    assert Finance.get_entitlement(user.id).status == "inactive"

    assert {:error, :not_found} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: future_subscription.id
             })

    assert {:ok, expired_subscription} =
             Finance.assign_package(membership.id, active_package.id, %{
               starts_on: Date.add(Date.utc_today(), -40),
               ends_on: Date.add(Date.utc_today(), -10)
             })

    assert Finance.get_entitlement(user.id).status == "inactive"

    assert {:error, :not_found} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: expired_subscription.id
             })
  end

  test "custom renewal periods require a distinct explicit end date" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "custom_period",
               name: "Custom Period",
               family: "hybrid",
               billing_period: "custom",
               base_price_cents: 5000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, subscription} =
             Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    assert {:error, :invalid_renewal_period} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               service_period_start: Date.utc_today()
             })

    assert {:error, :invalid_renewal_period} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               service_period_start: Date.utc_today(),
               service_period_end: Date.utc_today()
             })
  end

  test "records payments and exposes finance summary totals" do
    user = TestFixtures.user_fixture(%{role: :athlete})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "athlete",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 12500,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert payment.amount_cents == 12500
    assert Finance.financial_summary().totals.paid_revenue_cents >= 12500

    assert {:ok, _old_payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 9900,
               payment_method: "cash",
               payment_status: "paid",
               paid_on: Date.add(Date.utc_today(), -45)
             })

    scoped_summary = Finance.financial_summary(%{"days" => "30"})
    assert scoped_summary.period.days == 30
    assert scoped_summary.totals.paid_revenue_cents >= 12500
    refute scoped_summary.totals.paid_revenue_cents >= 22400
  end

  test "finance aggregate revenue is net of payment reversals" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 10_000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, _reversal} =
             Finance.reverse_payment(membership.id, payment.id, %{
               amount_cents: 3_000,
               reason: "Refund regression"
             })

    assert :ok = Finance.refresh_aggregates()

    summary = Finance.financial_summary()

    aggregate_paid =
      summary.aggregates
      |> Enum.reduce(0, &(&1.paid_revenue_cents + &2))

    monthly_paid =
      summary.monthly_revenue
      |> Enum.reduce(0, &(&1.paid_revenue_cents + &2))

    assert summary.totals.paid_revenue_cents == 7_000
    assert aggregate_paid == 7_000
    assert monthly_paid == 7_000
  end

  test "payment reversals are attributed to the original payment window" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, old_payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 8_000,
               payment_method: "cash",
               payment_status: "paid",
               paid_on: Date.add(Date.utc_today(), -45)
             })

    assert {:ok, _reversal} =
             Finance.reverse_payment(membership.id, old_payment.id, %{
               amount_cents: 3_000,
               reason: "Old period refund"
             })

    summary = Finance.financial_summary(%{"days" => "30"})

    assert summary.totals.paid_revenue_cents == 0
  end

  test "creates manual credit entries and applies available credit to payments" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    manual_credit_request_id = Ecto.UUID.generate()

    assert {:ok, credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 3000,
               description: "Goodwill credit",
               source_type: "promo_credit",
               currency: "USD",
               occurred_on: ~D[2020-01-01],
               idempotency_key: "caller-controlled-key",
               request_id: manual_credit_request_id
             })

    assert credit.amount_cents == 3000
    assert credit.entry_type == "grant"
    assert credit.source_type == "manual_credit"
    assert credit.currency == "EUR"
    assert credit.occurred_on == Date.utc_today()
    assert credit.idempotency_key != "caller-controlled-key"

    assert {:ok, ^credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 3000,
               description: "Goodwill credit",
               request_id: manual_credit_request_id
             })

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, failed_payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "failed"
             })

    assert {:error, :payment_not_creditable} =
             Finance.apply_credit_to_payment(membership.id, failed_payment.id, %{
               amount_cents: 100
             })

    assert {:ok, application} =
             Finance.apply_credit_to_payment(membership.id, payment.id, %{
               amount_cents: 1200,
               description: "Apply credit to payment"
             })

    assert application.amount_cents == -1200
    assert application.entry_type == "application"
    assert application.membership_payment_id == payment.id

    profile = Finance.get_member_profile(user.id)
    assert profile.credit_balance == 1800
    assert Enum.map(profile.credit_ledger_entries, & &1.id) == [application.id, credit.id]

    assert {:error, :insufficient_credit_balance} =
             Finance.apply_credit_to_payment(membership.id, payment.id, %{amount_cents: 4000})

    assert {:ok, _extra_credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 5000,
               description: "Capacity test credit"
             })

    assert {:error, :credit_exceeds_payment_amount} =
             Finance.apply_credit_to_payment(membership.id, payment.id, %{amount_cents: 3900})
  end

  test "reverses payment credit applications and restores member credit balance" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, _credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 2000,
               description: "Payment reversal credit"
             })

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, application} =
             Finance.apply_credit_to_payment(membership.id, payment.id, %{
               amount_cents: 1200,
               description: "Apply credit to payment"
             })

    profile_after_application = Finance.get_member_profile(user.id)
    assert profile_after_application.credit_balance == 800

    applied_entry =
      Enum.find(profile_after_application.credit_ledger_entries, &(&1.id == application.id))

    assert applied_entry.reversed_cents == 0
    assert applied_entry.remaining_reversible_cents == 1200

    assert {:ok, reversal} =
             Finance.reverse_credit_ledger_entry(membership.id, application.id, %{
               amount_cents: 1200,
               reason: "Admin correction"
             })

    assert reversal.amount_cents == 1200
    assert reversal.entry_type == "reversal"
    assert reversal.reversed_credit_ledger_entry_id == application.id

    profile_after_reversal = Finance.get_member_profile(user.id)
    assert profile_after_reversal.credit_balance == 2000

    restored_entry =
      Enum.find(profile_after_reversal.credit_ledger_entries, &(&1.id == application.id))

    assert restored_entry.reversed_cents == 1200
    assert restored_entry.remaining_reversible_cents == 0

    assert {:error, :credit_reversal_exceeds_application} =
             Finance.reverse_credit_ledger_entry(membership.id, application.id, %{amount_cents: 1})
  end

  test "creates invoices, applies payments and credits, and derives entitlement" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "invoice monthly",
               name: "Invoice Monthly",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 9000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, subscription} =
             Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    assert {:ok, invoice} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               service_period_start: Date.utc_today(),
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert invoice.invoice_type == "renewal"
    assert invoice.status == "draft"
    assert invoice.total_cents == 9000
    assert invoice.invoice_number =~ ~r/^INV-\d{6}-INVOICEMONTH-20\d{12}$/
    assert [line] = invoice.lines
    assert line.package_code_snapshot == "invoice_monthly"

    assert {:ok, issued_invoice} = Finance.issue_invoice(invoice.id)
    assert issued_invoice.status == "issued"
    assert issued_invoice.balance_due_cents == 9000

    assert Finance.get_entitlement(user.id).status == "grace"

    assert {:ok, _credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 3000,
               description: "Invoice credit"
             })

    assert {:ok, credit_application} =
             Finance.apply_credit_to_invoice(membership.id, invoice.id, %{
               amount_cents: 3000,
               description: "Apply credit to renewal"
             })

    assert credit_application.amount_cents == -3000
    assert credit_application.finance_invoice_id == invoice.id

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: invoice.id,
               amount_cents: 6000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert payment.finance_invoice_id == invoice.id

    profile = Finance.get_member_profile(user.id)
    assert [paid_invoice] = profile.invoices
    assert paid_invoice.status == "paid"
    assert paid_invoice.balance_due_cents == 0
    assert profile.entitlement.status == "active"

    summary = Finance.financial_summary()
    assert summary.totals.renewal_invoices_issued_count == 1
    assert summary.totals.renewal_invoices_paid_count == 1
    assert summary.totals.renewal_conversion_percent == 100.0
    assert summary.totals.invoice_credit_offset_cents == 3000
  end

  test "package-linked invoice partial payments keep balance due visible across finance read models" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "balance_package",
               name: "Balance Package",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 10_000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, subscription} =
             Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert invoice.membership_package_subscription_id == subscription.id
    assert invoice.total_cents == 10_000
    assert invoice.invoice_number =~ ~r/^INV-\d{6}-BALANCEPACKA-20\d{12}$/
    assert [line] = invoice.lines
    assert line.membership_package_subscription_id == subscription.id
    assert line.line_type == "membership_package"
    assert line.unit_amount_cents == 10_000
    assert line.package_code_snapshot == "balance_package"

    assert {:ok, issued_invoice} = Finance.issue_invoice(invoice.id)
    assert issued_invoice.balance_due_cents == 10_000

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: invoice.id,
               amount_cents: 4_000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert payment.finance_invoice_id == invoice.id

    profile = Finance.get_member_profile(user.id)
    open_invoice = Enum.find(profile.invoices, &(&1.id == invoice.id))
    assert open_invoice.status == "partially_paid"
    assert open_invoice.paid_cents == 4_000
    assert open_invoice.balance_due_cents == 6_000
    assert profile.entitlement.status == "grace"

    assert Finance.membership_outstanding_balance_cents(membership.id) == 6_000
    assert Finance.invoice_balance_due_map([invoice.id]) == %{invoice.id => 6_000}
    assert Finance.total_outstanding_balance_cents() >= 6_000

    member_summary =
      Finance.search_member_summaries(%{user_ids: [user.id], limit: 1})
      |> Map.fetch!(user.id)

    assert member_summary.outstanding_balance_cents == 6_000

    assert {:ok, my_finance} = MilosTraining.Application.GetMyFinance.call(user.id)
    assert my_finance.total_outstanding_balance_cents == 6_000

    assert Enum.any?(
             my_finance.invoices,
             &(&1.id == invoice.id and &1.balance_due_cents == 6_000)
           )

    summary = Finance.financial_summary()
    assert summary.totals.outstanding_invoice_balance_cents >= 6_000
  end

  test "refunds invoice payments and reverses invoice credit offsets before voiding" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 6000,
               description: "Refundable invoice",
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, issued_invoice} = Finance.issue_invoice(invoice.id)
    assert issued_invoice.status == "issued"

    assert {:ok, _credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 1000,
               description: "Refundable invoice credit"
             })

    assert {:ok, credit_application} =
             Finance.apply_credit_to_invoice(membership.id, invoice.id, %{amount_cents: 1000})

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: invoice.id,
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert Finance.get_member_profile(user.id).invoices |> hd() |> Map.fetch!(:status) == "paid"

    assert {:error, :invoice_has_allocations} = Finance.void_invoice(invoice.id)

    assert {:ok, payment_reversal} =
             Finance.reverse_payment(membership.id, payment.id, %{
               amount_cents: 5000,
               reason: "Cash refund"
             })

    assert payment_reversal.membership_payment_id == payment.id
    assert payment_reversal.finance_invoice_id == invoice.id
    assert payment_reversal.amount_cents == 5000

    refunded_profile = Finance.get_member_profile(user.id)
    refunded_invoice = hd(refunded_profile.invoices)
    assert refunded_invoice.status == "partially_paid"
    assert refunded_invoice.balance_due_cents == 5000
    assert refunded_invoice.paid_cents == 0
    assert [^payment_reversal] = refunded_profile.payment_reversals

    assert {:error, :payment_reversal_exceeds_payment_amount} =
             Finance.reverse_payment(membership.id, payment.id, %{amount_cents: 1})

    assert {:ok, credit_reversal} =
             Finance.reverse_credit_ledger_entry(membership.id, credit_application.id, %{
               amount_cents: 1000,
               reason: "Restore credit"
             })

    assert credit_reversal.reversed_credit_ledger_entry_id == credit_application.id

    reopened_profile = Finance.get_member_profile(user.id)
    reopened_invoice = hd(reopened_profile.invoices)
    assert reopened_invoice.status == "issued"
    assert reopened_invoice.balance_due_cents == 6000
    assert reopened_invoice.credit_applied_cents == 0
    assert reopened_profile.credit_balance == 1000

    restored_invoice_credit =
      Enum.find(reopened_profile.credit_ledger_entries, &(&1.id == credit_application.id))

    assert restored_invoice_credit.reversed_cents == 1000
    assert restored_invoice_credit.remaining_reversible_cents == 0

    assert {:ok, voided_invoice} = Finance.void_invoice(invoice.id)
    assert voided_invoice.status == "void"
  end

  test "finance credit analytics are net of invoice credit restorations" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, _grant} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 5_000,
               description: "Credit analytics regression"
             })

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 4_000,
               description: "Credit analytics invoice",
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, invoice} = Finance.issue_invoice(invoice.id)

    assert {:ok, application} =
             Finance.apply_credit_to_invoice(membership.id, invoice.id, %{
               amount_cents: 3_000,
               description: "Apply credit"
             })

    assert {:ok, _reversal} =
             Finance.reverse_credit_ledger_entry(membership.id, application.id, %{
               amount_cents: 1_000,
               reason: "Restore credit"
             })

    assert :ok = Finance.refresh_aggregates()

    summary = Finance.financial_summary()

    aggregate_totals =
      Enum.reduce(summary.aggregates, %{granted: 0, applied: 0, balance: 0}, fn row, acc ->
        %{
          granted: acc.granted + row.credit_granted_cents,
          applied: acc.applied + row.credit_applied_cents,
          balance: acc.balance + row.credit_balance_cents
        }
      end)

    assert summary.totals.invoice_credit_offset_cents == 2_000
    assert aggregate_totals.granted == 5_000
    assert aggregate_totals.applied == 2_000
    assert aggregate_totals.balance == 3_000
  end

  test "voiding overdue invoices clears entitlement blocking and queues expose invoice debt" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 4500,
               description: "Late charge",
               due_date: Date.add(Date.utc_today(), -2)
             })

    assert {:ok, overdue_invoice} = Finance.issue_invoice(invoice.id)
    assert overdue_invoice.status == "overdue"
    assert Finance.get_entitlement(user.id).status == "blocked"

    assert {:ok, _partial_payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: invoice.id,
               amount_cents: 1,
               payment_method: "cash",
               payment_status: "paid"
             })

    partial_profile = Finance.get_member_profile(user.id)
    partial_invoice = Enum.find(partial_profile.invoices, &(&1.id == invoice.id))
    assert partial_invoice.status == "overdue"
    assert partial_invoice.balance_due_cents == 4499
    assert Finance.get_entitlement(user.id).status == "blocked"

    summary = Finance.financial_summary()
    assert summary.totals.overdue_invoice_balance_cents >= 4499

    queues = Finance.operational_queues(%{"limit" => "10"})
    assert Enum.any?(queues.overdue_invoices, &(&1.id == invoice.id))

    assert {:error, :invoice_has_allocations} = Finance.void_invoice(invoice.id)
    assert Finance.get_entitlement(user.id).status == "blocked"
  end

  test "rejects invoice lines linked to another membership package subscription" do
    user = TestFixtures.user_fixture(%{role: :member})
    other_user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, other_membership} =
             Finance.upsert_membership(other_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, package} =
             Finance.create_package(%{
               code: "foreign_line_package",
               name: "Foreign Line Package",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 1000
             })

    assert {:ok, other_subscription} =
             Finance.assign_package(other_membership.id, package.id, %{})

    assert {:error, {:membership_mismatch, :membership_package_subscription_id}} =
             Finance.create_invoice(membership.id, %{
               lines: [
                 %{
                   membership_package_subscription_id: other_subscription.id,
                   line_type: "membership_package",
                   description: "Foreign subscription",
                   quantity: 1,
                   unit_amount_cents: 1000
                 }
               ]
             })
  end

  test "rejects manual invoice line discounts that exceed the line subtotal" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:error, :invoice_line_discount_exceeds_subtotal} =
             Finance.create_invoice(membership.id, %{
               lines: [
                 %{
                   line_type: "manual_charge",
                   description: "Impossible discount",
                   quantity: 1,
                   unit_amount_cents: 1000,
                   discount_cents: 5000
                 }
               ]
             })
  end

  test "rejects invalid invoice line quantity and money input instead of coercing it" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    for bad_line <- [
          %{quantity: 0, unit_amount_cents: 1000},
          %{quantity: -1, unit_amount_cents: 1000},
          %{quantity: "many", unit_amount_cents: 1000},
          %{quantity: 1, unit_amount_cents: "ten"},
          %{quantity: 1, unit_amount_cents: 1000, discount_cents: "none"}
        ] do
      assert {:error, :invalid_invoice_line_amount} =
               Finance.create_invoice(membership.id, %{
                 lines: [
                   Map.merge(
                     %{
                       line_type: "manual_charge",
                       description: "Invalid line"
                     },
                     bad_line
                   )
                 ]
               })
    end
  end

  test "rejects payments attached to invalid invoice states or over invoice balance" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, draft_invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 1000,
               description: "Draft payment rejection"
             })

    assert {:error, :invoice_not_issued} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: draft_invoice.id,
               amount_cents: 1000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, issued_invoice} = Finance.issue_invoice(draft_invoice.id)

    assert {:error, :payment_exceeds_invoice_balance} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: issued_invoice.id,
               amount_cents: 1001,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, _payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: issued_invoice.id,
               amount_cents: 1000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:error, :invoice_already_paid} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: issued_invoice.id,
               amount_cents: 1,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, void_candidate} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 500,
               description: "Void payment rejection"
             })

    assert {:ok, issued_void_candidate} = Finance.issue_invoice(void_candidate.id)
    assert {:ok, _voided_invoice} = Finance.void_invoice(issued_void_candidate.id)

    assert {:error, :invoice_void} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: issued_void_candidate.id,
               amount_cents: 500,
               payment_method: "cash",
               payment_status: "paid"
             })
  end

  test "rejects credit application to draft invoices" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, _credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 1000,
               description: "Draft invoice credit"
             })

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 1000,
               description: "Draft invoice"
             })

    assert {:error, :invoice_not_issued} =
             Finance.apply_credit_to_invoice(membership.id, invoice.id, %{amount_cents: 500})
  end

  test "rejects voiding invoices with attached payments or credit offsets" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, payment_invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 1000,
               description: "Allocated payment invoice"
             })

    assert {:ok, payment_invoice} = Finance.issue_invoice(payment_invoice.id)

    assert {:ok, _payment} =
             Finance.record_payment(membership.id, %{
               finance_invoice_id: payment_invoice.id,
               amount_cents: 500,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:error, :invoice_has_allocations} = Finance.void_invoice(payment_invoice.id)

    assert {:ok, credit_invoice} =
             Finance.create_invoice(membership.id, %{
               amount_cents: 1000,
               description: "Allocated credit invoice"
             })

    assert {:ok, credit_invoice} = Finance.issue_invoice(credit_invoice.id)

    assert {:ok, _credit} =
             Finance.create_manual_credit(membership.id, %{
               amount_cents: 1000,
               description: "Invoice allocation credit"
             })

    assert {:ok, _credit_application} =
             Finance.apply_credit_to_invoice(membership.id, credit_invoice.id, %{
               amount_cents: 500
             })

    assert {:error, :invoice_has_allocations} = Finance.void_invoice(credit_invoice.id)
  end

  test "rejects duplicate renewal invoices for the same subscription and service period" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "duplicate_renewal_package",
               name: "Duplicate Renewal Package",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 9000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, subscription} =
             Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    period_start = Date.utc_today()

    assert {:ok, _invoice} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               service_period_start: period_start
             })

    assert {:error, :duplicate_renewal_invoice} =
             Finance.generate_renewal_invoice(membership.id, %{
               membership_package_subscription_id: subscription.id,
               service_period_start: period_start
             })
  end

  test "exposes operational queues for finance follow-up work" do
    user = TestFixtures.user_fixture(%{role: :member})
    expired_user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 9000,
               payment_method: "bank_transfer",
               payment_status: "pending"
             })

    assert {:ok, expired_membership} =
             Finance.upsert_membership(expired_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), -7)
             })

    queues = Finance.operational_queues(%{"expires_within_days" => "30", "limit" => "10"})

    assert Enum.any?(queues.expiring_memberships, &(&1.id == membership.id))
    refute Enum.any?(queues.expiring_memberships, &(&1.id == expired_membership.id))
    assert Enum.any?(queues.pending_payments, &(&1.id == payment.id))
  end

  test "creates promotion codes and records redemptions against memberships" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "promo"
             })

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Founders",
               starts_on: Date.add(Date.utc_today(), -7),
               ends_on: Date.add(Date.utc_today(), 30)
             })

    assert {:ok, code} =
             Finance.create_promotion_code(campaign.id, %{
               code: "founders 20",
               discount_type: "percent",
               discount_value: 20
             })

    assert code.code == "FOUNDERS-20"

    assert {:ok, redemption} =
             Finance.redeem_promotion(membership.id, %{
               promotion_code: "FOUNDERS-20"
             })

    assert redemption.promotion_campaign_id == campaign.id
    assert redemption.promotion_code_id == code.id
    assert redemption.discount_type_snapshot == "percent"
    assert redemption.discount_value_snapshot == 20
  end

  test "normalizes fixed promotion aliases and enforces campaign lifecycle and redemption limits" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "promo"
             })

    today = Date.utc_today()

    assert {:ok, inactive_campaign} =
             Finance.create_promotion_campaign(%{
               name: "Inactive",
               active: false,
               starts_on: Date.add(today, -1),
               ends_on: Date.add(today, 1)
             })

    assert {:ok, inactive_code} =
             Finance.create_promotion_code(inactive_campaign.id, %{
               code: "inactive 5",
               discount_type: "fixed",
               discount_value: 500
             })

    assert inactive_code.discount_type == "fixed_amount"

    assert {:error, :promotion_campaign_inactive} =
             Finance.redeem_promotion(membership.id, %{promotion_code: "INACTIVE-5"})

    assert {:ok, future_campaign} =
             Finance.create_promotion_campaign(%{
               name: "Future",
               starts_on: Date.add(today, 1),
               ends_on: Date.add(today, 10)
             })

    assert {:ok, _future_code} =
             Finance.create_promotion_code(future_campaign.id, %{
               code: "future 5",
               discount_type: "fixed_amount",
               discount_value: 500
             })

    assert {:error, :promotion_campaign_not_started} =
             Finance.redeem_promotion(membership.id, %{promotion_code: "FUTURE-5"})

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Limited",
               starts_on: Date.add(today, -1),
               ends_on: Date.add(today, 1)
             })

    assert {:ok, _limited_code} =
             Finance.create_promotion_code(campaign.id, %{
               code: "limited 5",
               discount_type: "fixed_amount",
               discount_value: 500,
               max_redemptions: 1
             })

    assert {:ok, first_redemption} =
             Finance.redeem_promotion(membership.id, %{promotion_code: "LIMITED-5"})

    assert first_redemption.discount_type_snapshot == "fixed_amount"

    assert {:error, :promotion_code_max_redemptions_reached} =
             Finance.redeem_promotion(membership.id, %{promotion_code: "LIMITED-5"})
  end

  test "validates promotion campaign dates and percentage limits" do
    assert {:error, campaign_changeset} =
             Finance.create_promotion_campaign(%{
               name: "Backwards",
               starts_on: ~D[2026-06-20],
               ends_on: ~D[2026-06-10]
             })

    assert "must be on or after the start date" in errors_on(campaign_changeset).ends_on

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Valid",
               starts_on: ~D[2026-06-10],
               ends_on: ~D[2026-06-20]
             })

    assert {:error, code_changeset} =
             Finance.create_promotion_code(campaign.id, %{
               code: "TOO-MUCH",
               discount_type: "percent",
               discount_value: 101
             })

    assert "must be less than or equal to 100" in errors_on(code_changeset).discount_value
  end

  test "serializes concurrent promotion redemptions at the code limit" do
    users = Enum.map(1..2, fn _ -> TestFixtures.user_fixture(%{role: :member}) end)

    memberships =
      Enum.map(users, fn user ->
        {:ok, membership} =
          Finance.upsert_membership(user.id, %{
            user_type_snapshot: "member",
            status: "active",
            signup_source: "promo"
          })

        membership
      end)

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Concurrent limit",
               starts_on: Date.add(Date.utc_today(), -1),
               ends_on: Date.add(Date.utc_today(), 1)
             })

    assert {:ok, _code} =
             Finance.create_promotion_code(campaign.id, %{
               code: "ONE-ONLY",
               discount_type: "fixed_amount",
               discount_value: 500,
               max_redemptions: 1
             })

    results =
      memberships
      |> Enum.map(fn membership ->
        Task.async(fn ->
          Finance.redeem_promotion(membership.id, %{promotion_code: "ONE-ONLY"})
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, :promotion_code_max_redemptions_reached}, &1)
           ) == 1
  end

  test "finance aggregates do not multiply payment or discount facts across child joins" do
    user = TestFixtures.user_fixture(%{role: :member})
    referrer = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, _referrer_membership} =
             Finance.upsert_membership(referrer.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "promo"
             })

    assert {:ok, package_a} =
             Finance.create_package(%{
               code: "aggregate_a",
               name: "Aggregate A",
               family: "hybrid",
               billing_period: "monthly",
               base_price_cents: 1000
             })

    assert {:ok, package_b} =
             Finance.create_package(%{
               code: "aggregate_b",
               name: "Aggregate B",
               family: "hybrid",
               billing_period: "monthly",
               base_price_cents: 2000
             })

    assert {:ok, _subscription_a} = Finance.assign_package(membership.id, package_a.id, %{})
    assert {:ok, _subscription_b} = Finance.assign_package(membership.id, package_b.id, %{})

    assert {:ok, _payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 12_500,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Aggregate Promo",
               starts_on: Date.add(Date.utc_today(), -1),
               ends_on: Date.add(Date.utc_today(), 1)
             })

    assert {:ok, _code_a} =
             Finance.create_promotion_code(campaign.id, %{
               code: "aggregate one",
               discount_type: "fixed_amount",
               discount_value: 100
             })

    assert {:ok, _code_b} =
             Finance.create_promotion_code(campaign.id, %{
               code: "aggregate two",
               discount_type: "fixed_amount",
               discount_value: 200
             })

    assert {:ok, _redemption_a} =
             Finance.redeem_promotion(membership.id, %{promotion_code: "AGGREGATE-ONE"})

    assert {:ok, _redemption_b} =
             Finance.redeem_promotion(membership.id, %{
               promotion_code: "AGGREGATE-TWO",
               params: %{realized_discount_cents: 200}
             })

    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Aggregate referrals",
               reward_type: "credit",
               reward_value: 500
             })

    assert {:ok, event} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: user.id,
               membership_id: membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "member"
             })

    assert {:ok, event} = Finance.update_referral_status(event.id, "approved")

    assert {:ok, reward} =
             Finance.create_referral_reward(event.id, %{reward_type: "credit", reward_value: 500})

    assert {:ok, reward} = Finance.update_referral_reward_status(reward.id, "approved")
    assert {:ok, _reward} = Finance.update_referral_reward_status(reward.id, "applied")

    assert :ok = Finance.refresh_aggregates()

    aggregate_totals =
      Finance.financial_summary().aggregates
      |> Enum.reduce(%{paid: 0, discounts: 0, fixed_count: 0, credit_balance: 0}, fn row, acc ->
        %{
          paid: acc.paid + row.paid_revenue_cents,
          discounts: acc.discounts + row.promotion_realized_discount_cents,
          fixed_count: acc.fixed_count + row.promotion_fixed_amount_redemption_count,
          credit_balance: acc.credit_balance + row.credit_balance_cents
        }
      end)

    assert aggregate_totals.paid == 12_500
    assert aggregate_totals.discounts == 200
    assert aggregate_totals.fixed_count == 2
    assert aggregate_totals.credit_balance == 500
    assert length(Finance.financial_summary().monthly_revenue) == 24
  end

  test "creates referral events and manual rewards" do
    referrer = TestFixtures.user_fixture(%{role: :member})
    referred = TestFixtures.user_fixture(%{role: :athlete})

    assert {:ok, _referrer_membership} =
             Finance.upsert_membership(referrer.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, membership} =
             Finance.upsert_membership(referred.id, %{
               user_type_snapshot: "athlete",
               status: "trial",
               signup_source: "referral",
               referred_by_user_id: referrer.id
             })

    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Member get member",
               reward_type: "credit",
               reward_value: 1000
             })

    assert {:ok, event} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })

    assert {:ok, event} = Finance.update_referral_status(event.id, "approved")

    assert Enum.map(Finance.list_referral_programs(), & &1.id) == [program.id]

    assert {:ok, reward} = Finance.create_referral_reward(event.id, %{})

    assert reward.referral_event_id == event.id
    assert reward.recipient_user_id == referrer.id
    assert reward.membership_id == membership.id
    assert reward.reward_type == "credit"
    assert reward.reward_value == 1000

    assert {:ok, applied_reward} = Finance.update_referral_reward_status(reward.id, "applied")
    assert applied_reward.status == "applied"
    assert Finance.get_member_profile(referrer.id).credit_balance == 1000

    assert {:ok, rejected_reward} = Finance.update_referral_reward_status(reward.id, "rejected")
    assert rejected_reward.status == "rejected"
    assert Finance.get_member_profile(referrer.id).credit_balance == 0

    assert {:ok, reapplied_reward} = Finance.update_referral_reward_status(reward.id, "applied")
    assert reapplied_reward.status == "applied"
    assert Finance.get_member_profile(referrer.id).credit_balance == 1000

    another_referred = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, another_membership} =
             Finance.upsert_membership(another_referred.id, %{
               user_type_snapshot: "member",
               status: "trial",
               signup_source: "referral",
               referred_by_user_id: referrer.id
             })

    assert {:ok, another_event} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: another_referred.id,
               membership_id: another_membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "member"
             })

    assert {:ok, another_event} = Finance.update_referral_status(another_event.id, "approved")
    assert {:ok, another_reward} = Finance.create_referral_reward(another_event.id, %{})

    assert {:ok, _another_applied_reward} =
             Finance.update_referral_reward_status(another_reward.id, "applied")

    assert Finance.get_member_profile(referrer.id).credit_balance == 2000

    assert {:ok, _rejected_reward} = Finance.update_referral_reward_status(reward.id, "rejected")

    assert Finance.get_member_profile(referrer.id).credit_balance == 1000
  end

  test "updates referral programs" do
    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Original referral",
               reward_type: "manual",
               reward_value: 0,
               active: true
             })

    assert {:ok, updated} =
             Finance.update_referral_program(program.id, %{
               name: "Bring a friend",
               description: "1+1",
               reward_type: "credit",
               reward_value: 750,
               active: false
             })

    assert updated.id == program.id
    assert updated.name == "Bring a friend"
    assert updated.description == "1+1"
    assert updated.reward_type == "credit"
    assert updated.reward_value == 750
    assert updated.active == false
  end

  test "requires an active referral program for new referral events" do
    referrer = TestFixtures.user_fixture(%{role: :member})
    referred = TestFixtures.user_fixture(%{role: :athlete})

    assert {:error, :referral_program_required} =
             Finance.create_referral_event(%{
               referrer_user_id: referrer.id,
               referred_user_id: referred.id
             })

    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Inactive program",
               active: false,
               reward_type: "credit",
               reward_value: 500
             })

    assert {:error, :referral_program_inactive} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: Ecto.UUID.generate(),
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })
  end

  test "rejects finance facts linked to another membership" do
    user = TestFixtures.user_fixture(%{role: :member})
    other_user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, other_membership} =
             Finance.upsert_membership(other_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, package} =
             Finance.create_package(%{
               code: "mismatch_package",
               name: "Mismatch Package",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 1000
             })

    assert {:ok, other_subscription} =
             Finance.assign_package(other_membership.id, package.id, %{})

    assert {:error, {:membership_mismatch, :membership_package_subscription_id}} =
             Finance.record_payment(membership.id, %{
               amount_cents: 1000,
               payment_method: "cash",
               payment_status: "paid",
               membership_package_subscription_id: other_subscription.id
             })

    assert {:ok, other_payment} =
             Finance.record_payment(other_membership.id, %{
               amount_cents: 1000,
               payment_method: "cash",
               payment_status: "paid"
             })

    assert {:error, {:membership_mismatch, :membership_payment_id}} =
             Finance.redeem_promotion(membership.id, %{
               promotion_campaign_id: Ecto.UUID.generate(),
               discount_type_snapshot: "manual",
               discount_value_snapshot: 100,
               membership_payment_id: other_payment.id
             })
  end

  test "derives membership lifecycle status from expiration dates" do
    expired_user = TestFixtures.user_fixture(%{role: :member})
    expiring_user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, expired_membership} =
             Finance.upsert_membership(expired_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), -1)
             })

    assert expired_membership.status == "expired"

    assert {:ok, expiring_membership} =
             Finance.upsert_membership(expiring_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct",
               expires_on: Date.add(Date.utc_today(), 7)
             })

    assert expiring_membership.status == "expiring"
  end

  test "requires explicit value for manual campaign redemptions" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "promo"
             })

    assert {:ok, campaign} =
             Finance.create_promotion_campaign(%{
               name: "Manual Campaign",
               starts_on: Date.add(Date.utc_today(), -1),
               ends_on: Date.add(Date.utc_today(), 1)
             })

    assert {:error, :promotion_discount_required} =
             Finance.redeem_promotion(membership.id, %{promotion_campaign_id: campaign.id})

    assert {:ok, redemption} =
             Finance.redeem_promotion(membership.id, %{
               promotion_campaign_id: campaign.id,
               discount_type_snapshot: "manual",
               discount_value_snapshot: 100
             })

    assert redemption.discount_value_snapshot == 100
  end

  test "rejects self-referrals, mismatched referral memberships, early rewards, and duplicate rewards" do
    referrer = TestFixtures.user_fixture(%{role: :member})
    referred = TestFixtures.user_fixture(%{role: :athlete})
    other_user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(referred.id, %{
               user_type_snapshot: "athlete",
               status: "trial",
               signup_source: "referral"
             })

    assert {:ok, other_membership} =
             Finance.upsert_membership(other_user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Policy referrals",
               reward_type: "credit",
               reward_value: 500
             })

    assert {:error, :self_referral_not_allowed} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referrer.id,
               membership_id: membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "member"
             })

    assert {:error, :referral_membership_required} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })

    assert {:error, :referral_membership_user_mismatch} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: other_membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })

    assert {:error, :referral_referrer_role_ineligible} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: membership.id,
               referrer_role_snapshot: "admin",
               referred_role_snapshot: "athlete"
             })

    assert {:ok, event} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })

    assert {:error, :referral_event_not_approved} =
             Finance.create_referral_reward(event.id, %{reward_type: "credit", reward_value: 500})

    assert {:ok, approved_event} = Finance.update_referral_status(event.id, "approved")

    assert {:ok, _reward} =
             Finance.create_referral_reward(approved_event.id, %{
               reward_type: "credit",
               reward_value: 500
             })

    assert {:error, :referral_reward_already_exists} =
             Finance.create_referral_reward(approved_event.id, %{
               reward_type: "credit",
               reward_value: 500
             })
  end

  test "guards referral event and reward status transitions" do
    referrer = TestFixtures.user_fixture(%{role: :member})
    referred = TestFixtures.user_fixture(%{role: :athlete})

    assert {:ok, _referrer_membership} =
             Finance.upsert_membership(referrer.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, referred_membership} =
             Finance.upsert_membership(referred.id, %{
               user_type_snapshot: "athlete",
               status: "trial",
               signup_source: "referral",
               referred_by_user_id: referrer.id
             })

    assert {:ok, program} =
             Finance.create_referral_program(%{
               name: "Lifecycle referrals",
               reward_type: "credit",
               reward_value: 1000
             })

    assert {:ok, event} =
             Finance.create_referral_event(%{
               referral_program_id: program.id,
               referrer_user_id: referrer.id,
               referred_user_id: referred.id,
               membership_id: referred_membership.id,
               referrer_role_snapshot: "member",
               referred_role_snapshot: "athlete"
             })

    assert {:error, :invalid_referral_status_transition} =
             Finance.update_referral_status(event.id, "applied")

    assert {:ok, approved_event} = Finance.update_referral_status(event.id, "approved")
    assert approved_event.status == "approved"

    assert {:ok, reward} =
             Finance.create_referral_reward(event.id, %{
               reward_type: "credit",
               reward_value: 1000,
               status: "pending"
             })

    assert {:ok, applied_reward} = Finance.update_referral_reward_status(reward.id, "applied")
    assert applied_reward.status == "applied"
    assert applied_reward.applied_at

    referrer_profile = Finance.get_member_profile(referrer.id)
    assert referrer_profile.credit_balance == 1000
    assert [credit_entry] = referrer_profile.credit_ledger_entries
    assert credit_entry.referral_reward_id == reward.id

    assert {:ok, _applied_reward} = Finance.update_referral_reward_status(reward.id, "applied")
    assert length(Finance.get_member_profile(referrer.id).credit_ledger_entries) == 1
  end

  test "search_member_summaries includes last_payment_on and last_payment_amount_cents" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert {:ok, _old_payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 5000,
               payment_method: "cash",
               payment_status: "paid",
               paid_on: ~D[2026-01-01]
             })

    assert {:ok, _new_payment} =
             Finance.record_payment(membership.id, %{
               amount_cents: 8000,
               payment_method: "cash",
               payment_status: "paid",
               paid_on: ~D[2026-06-01]
             })

    summaries = Finance.search_member_summaries(%{user_ids: [user.id], limit: 10})
    profile = Map.get(summaries, user.id)

    assert profile.last_payment_on == ~D[2026-06-01]
    assert profile.last_payment_amount_cents == 8000
    assert profile.credit_balance == 0
    assert profile.credit_balance_cents == 0
  end

  test "search_member_summaries returns nil last_payment fields when no payments exist" do
    user = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, _membership} =
             Finance.upsert_membership(user.id, %{
               user_type_snapshot: "member",
               status: "trial",
               signup_source: "direct"
             })

    summaries = Finance.search_member_summaries(%{user_ids: [user.id], limit: 10})
    profile = Map.get(summaries, user.id)

    assert is_nil(profile.last_payment_on)
    assert is_nil(profile.last_payment_amount_cents)
  end

  test "applies non-credit referral rewards without creating credit grants" do
    referrer = TestFixtures.user_fixture(%{role: :member})
    referred = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, referrer_membership} =
             Finance.upsert_membership(referrer.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, referred_membership} =
             Finance.upsert_membership(referred.id, %{
               user_type_snapshot: "member",
               status: "trial",
               signup_source: "referral",
               referred_by_user_id: referrer.id
             })

    for reward_type <- ["manual", "discount", "free_period"] do
      assert {:ok, program} =
               Finance.create_referral_program(%{
                 name: "Non-credit #{reward_type}",
                 reward_type: reward_type,
                 reward_value: 0
               })

      assert {:ok, event} =
               Finance.create_referral_event(%{
                 referral_program_id: program.id,
                 referrer_user_id: referrer.id,
                 referred_user_id: referred.id,
                 membership_id: referred_membership.id,
                 referrer_role_snapshot: "member",
                 referred_role_snapshot: "member"
               })

      assert {:ok, event} = Finance.update_referral_status(event.id, "approved")
      assert {:ok, reward} = Finance.create_referral_reward(event.id, %{})
      assert {:ok, reward} = Finance.update_referral_reward_status(reward.id, "approved")
      assert {:ok, reward} = Finance.update_referral_reward_status(reward.id, "applied")
      assert reward.reward_type == reward_type
      assert reward.applied_at
    end

    profile = Finance.get_member_profile(referrer.id)
    assert profile.membership.id == referrer_membership.id
    assert profile.credit_balance == 0
    assert profile.credit_ledger_entries == []
  end
end
