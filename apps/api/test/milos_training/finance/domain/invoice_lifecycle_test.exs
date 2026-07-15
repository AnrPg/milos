defmodule MilosTraining.Finance.Domain.InvoiceLifecycleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.InvoiceLifecycle

  test "calculates line and invoice totals from line facts" do
    line = %{"quantity" => 2, "unit_amount_cents" => 3000, "discount_cents" => 500}

    assert InvoiceLifecycle.line_total(2, 3000, 500) == {:ok, 5500}

    assert InvoiceLifecycle.invoice_totals([
             Map.put(line, "total_cents", 5500)
           ]) == %{subtotal_cents: 6000, discount_cents: 500, total_cents: 5500}
  end

  test "rejects invoice line discounts above subtotal" do
    assert InvoiceLifecycle.line_total(1, 1000, 5000) ==
             {:error, :invoice_line_discount_exceeds_subtotal}

    assert InvoiceLifecycle.line_total(0, 1000, 0) == {:error, :invalid_invoice_line_amount}
    assert InvoiceLifecycle.line_total(1, -1000, 0) == {:error, :invalid_invoice_line_amount}
  end

  test "derives invoice status from paid and credited amounts" do
    today = ~D[2026-06-12]

    assert InvoiceLifecycle.status(10_000, 0, 0, Date.add(today, -1), today, "issued") ==
             "overdue"

    assert InvoiceLifecycle.status(10_000, 2500, 0, Date.add(today, 5), today, "issued") ==
             "partially_paid"

    assert InvoiceLifecycle.status(10_000, 2500, 0, Date.add(today, -1), today, "issued") ==
             "overdue"

    assert InvoiceLifecycle.status(10_000, 7000, 3000, Date.add(today, 5), today, "issued") ==
             "paid"

    assert InvoiceLifecycle.status(10_000, 10_000, 0, Date.add(today, 5), today, "void") ==
             "void"
  end

  test "validates payment and credit allocation state" do
    assert :ok = InvoiceLifecycle.validate_payment_application("issued", 1000, 1000)
    assert :ok = InvoiceLifecycle.validate_payment_application("partially_paid", 500, 1000)
    assert :ok = InvoiceLifecycle.validate_payment_application("overdue", 500, 1000)

    assert {:error, :invoice_not_issued} =
             InvoiceLifecycle.validate_payment_application("draft", 1000, 1000)

    assert {:error, :invoice_void} =
             InvoiceLifecycle.validate_payment_application("void", 1000, 1000)

    assert {:error, :invoice_already_paid} =
             InvoiceLifecycle.validate_payment_application("paid", 1000, 1000)

    assert {:error, :payment_exceeds_invoice_balance} =
             InvoiceLifecycle.validate_payment_application("issued", 1001, 1000)

    assert {:error, :invoice_not_issued} =
             InvoiceLifecycle.validate_credit_application("draft", 1000, 500, 1000)

    assert {:error, :invoice_already_paid} =
             InvoiceLifecycle.validate_credit_application("paid", 1000, 500, 1000)
  end

  test "validates payment reversal amount" do
    assert :ok = InvoiceLifecycle.validate_payment_reversal("paid", 5000, 1200, 3800)
    assert :ok = InvoiceLifecycle.validate_payment_reversal("waived", 5000, 0, 5000)

    assert {:error, :payment_not_reversible} =
             InvoiceLifecycle.validate_payment_reversal("pending", 5000, 0, 1000)

    assert {:error, :invalid_payment_reversal_amount} =
             InvoiceLifecycle.validate_payment_reversal("paid", 5000, 0, 0)

    assert {:error, :payment_reversal_exceeds_payment_amount} =
             InvoiceLifecycle.validate_payment_reversal("paid", 5000, 1200, 3801)
  end

  test "rejects voiding invoices with financial allocations" do
    assert :ok = InvoiceLifecycle.validate_void("issued", 0, 0)

    assert {:error, :invoice_has_allocations} =
             InvoiceLifecycle.validate_void("issued", 1000, 0)

    assert {:error, :invoice_has_allocations} =
             InvoiceLifecycle.validate_void("issued", 0, 1000)
  end

  test "derives entitlement from membership, subscription, and invoice facts" do
    today = ~D[2026-06-12]

    assert InvoiceLifecycle.entitlement(%{
             membership_status: "active",
             membership_expires_on: Date.add(today, 30),
             active_subscription?: true,
             open_invoice_count: 0,
             overdue_invoice_count: 0,
             today: today
           }).status == "active"

    assert InvoiceLifecycle.entitlement(%{
             membership_status: "active",
             membership_expires_on: Date.add(today, 30),
             active_subscription?: true,
             open_invoice_count: 1,
             overdue_invoice_count: 0,
             today: today
           }).status == "grace"

    assert InvoiceLifecycle.entitlement(%{
             membership_status: "active",
             membership_expires_on: Date.add(today, 30),
             active_subscription?: true,
             open_invoice_count: 1,
             overdue_invoice_count: 1,
             today: today
           }).status == "blocked"
  end

  test "advances renewal periods by calendar month and year boundaries" do
    assert InvoiceLifecycle.next_period("monthly", ~D[2026-01-31]) ==
             {~D[2026-01-31], ~D[2026-02-28]}

    assert InvoiceLifecycle.next_period("quarterly", ~D[2026-11-30]) ==
             {~D[2026-11-30], ~D[2027-02-28]}

    assert InvoiceLifecycle.next_period("annual", ~D[2024-02-29]) ==
             {~D[2024-02-29], ~D[2025-02-28]}
  end

  test "requires an explicit valid end date for custom renewal periods" do
    assert {:ok, {~D[2026-06-12], ~D[2026-08-15]}} =
             InvoiceLifecycle.renewal_period(
               "custom",
               ~D[2026-06-12],
               ~D[2026-08-15]
             )

    assert {:error, :invalid_renewal_period} =
             InvoiceLifecycle.renewal_period("custom", ~D[2026-06-12], nil)

    assert {:error, :invalid_renewal_period} =
             InvoiceLifecycle.renewal_period(
               "custom",
               ~D[2026-06-12],
               ~D[2026-06-11]
             )

    assert {:error, :invalid_renewal_period} =
             InvoiceLifecycle.renewal_period(
               "custom",
               ~D[2026-06-12],
               ~D[2026-06-12]
             )

    assert {:error, :invalid_billing_period} =
             InvoiceLifecycle.renewal_period("weekly", ~D[2026-06-12], nil)
  end
end
