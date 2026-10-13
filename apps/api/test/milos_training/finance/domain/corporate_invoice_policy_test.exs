defmodule MilosTraining.Finance.Domain.CorporateInvoicePolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.CorporateInvoicePolicy, as: Policy

  describe "period_to_invoice/4" do
    test "agreed billing invoices the current period in advance" do
      assert Policy.period_to_invoice("monthly", "agreed", ~D[2026-09-20], ~D[2026-10-12]) ==
               {:ok, {~D[2026-10-01], ~D[2026-10-31]}}
    end

    test "used billing invoices the previous period once it has ended" do
      assert Policy.period_to_invoice("monthly", "used", ~D[2026-09-20], ~D[2026-10-12]) ==
               {:ok, {~D[2026-09-01], ~D[2026-09-30]}}

      assert Policy.period_to_invoice("quarterly", "used", ~D[2026-01-05], ~D[2026-10-01]) ==
               {:ok, {~D[2026-07-01], ~D[2026-09-30]}}
    end

    test "periods that ended before the client existed are never invoiced" do
      assert Policy.period_to_invoice("monthly", "used", ~D[2026-10-03], ~D[2026-10-12]) ==
               :none
    end
  end

  test "due date follows the payment terms" do
    assert Policy.due_on(~D[2026-10-12], 14) == ~D[2026-10-26]
    assert Policy.due_on(~D[2026-10-12], 0) == ~D[2026-10-12]
  end

  describe "payments" do
    setup do
      %{invoice: %{status: "issued", total_cents: 10_000, due_on: ~D[2026-10-20]}}
    end

    test "a payment must be positive and fit the balance", %{invoice: invoice} do
      assert :ok = Policy.can_record_payment?(invoice, 4_000, 6_000)

      assert {:error, :payment_exceeds_balance} =
               Policy.can_record_payment?(invoice, 6_001, 6_000)

      assert {:error, :invalid_payment_amount} = Policy.can_record_payment?(invoice, 0, 6_000)

      assert {:error, :corporate_invoice_closed} =
               Policy.can_record_payment?(%{invoice | status: "void"}, 1, 1)
    end

    test "status follows the balance and the due date", %{invoice: invoice} do
      assert Policy.status_after_payments(invoice, 10_000, ~D[2026-10-25]) == "paid"
      assert Policy.status_after_payments(invoice, 4_000, ~D[2026-10-12]) == "issued"
      assert Policy.status_after_payments(invoice, 4_000, ~D[2026-10-21]) == "overdue"

      assert Policy.status_after_payments(%{invoice | status: "void"}, 0, ~D[2026-10-21]) ==
               "void"
    end

    test "only an unpaid open invoice can be voided", %{invoice: invoice} do
      assert :ok = Policy.can_void?(invoice, 0)
      assert {:error, :corporate_invoice_has_payments} = Policy.can_void?(invoice, 100)

      assert {:error, :corporate_invoice_closed} =
               Policy.can_void?(%{invoice | status: "paid"}, 0)
    end
  end

  test "reminders repeat every interval while overdue" do
    overdue = %{status: "overdue", last_reminded_on: nil}
    assert Policy.reminder_due?(overdue, ~D[2026-10-12], 7)
    refute Policy.reminder_due?(%{overdue | last_reminded_on: ~D[2026-10-08]}, ~D[2026-10-12], 7)
    assert Policy.reminder_due?(%{overdue | last_reminded_on: ~D[2026-10-05]}, ~D[2026-10-12], 7)
    refute Policy.reminder_due?(%{overdue | status: "issued"}, ~D[2026-10-12], 7)
  end
end
