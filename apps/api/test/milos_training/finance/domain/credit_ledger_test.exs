defmodule MilosTraining.Finance.Domain.CreditLedgerTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.CreditLedger

  test "validates credit application against balance and payment capacity" do
    assert :ok = CreditLedger.validate_application(1000, 500, 800)
    assert {:error, :invalid_credit_amount} = CreditLedger.validate_application(1000, 0, 800)

    assert {:error, :insufficient_credit_balance} =
             CreditLedger.validate_application(300, 500, 800)

    assert {:error, :credit_exceeds_payment_amount} =
             CreditLedger.validate_application(1000, 900, 800)
  end

  test "accepts positive referral reward grant values only" do
    assert {:ok, 1500} = CreditLedger.referral_reward_grant_amount(%{reward_value: 1500})

    assert {:error, :invalid_credit_amount} =
             CreditLedger.referral_reward_grant_amount(%{reward_value: 0})
  end

  test "validates payment status before credit application" do
    assert :ok = CreditLedger.validate_payment_status("paid")
    assert :ok = CreditLedger.validate_payment_status("pending")
    assert {:error, :payment_not_creditable} = CreditLedger.validate_payment_status("failed")
    assert {:error, :payment_not_creditable} = CreditLedger.validate_payment_status("refunded")
    assert {:error, :payment_not_creditable} = CreditLedger.validate_payment_status("waived")
  end

  test "validates credit application reversal amount" do
    original = %{amount_cents: -1200, source_type: "invoice_offset", entry_type: "invoice_offset"}

    assert :ok = CreditLedger.validate_reversal(original, 200, 1000)
    assert {:error, :invalid_credit_amount} = CreditLedger.validate_reversal(original, 0, 0)

    assert {:error, :credit_reversal_exceeds_application} =
             CreditLedger.validate_reversal(original, 300, 1000)

    assert {:error, :credit_entry_not_reversible} =
             CreditLedger.validate_reversal(%{amount_cents: 1200, entry_type: "grant"}, 0, 100)
  end
end
