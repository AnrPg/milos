defmodule Palee.Finance.Domain.ReceivedPaymentTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.ReceivedPayment

  test "the billing setup picks the document; an open invoice is settled whatever the mode" do
    assert ReceivedPayment.document("receipt", nil) == :receipt
    assert ReceivedPayment.document("invoice", nil) == :invoice
    assert ReceivedPayment.document(nil, "") == :invoice
    assert ReceivedPayment.document("receipt", "inv-1") == :settle_invoice
    assert ReceivedPayment.document("invoice", "inv-1") == :settle_invoice
  end

  test "validates key, method and amount before anything is written" do
    ok = %{"idempotency_key" => "k", "payment_method" => "cash", "amount_cents" => 100}
    assert ReceivedPayment.validate(ok) == :ok
    assert ReceivedPayment.validate(%{ok | "amount_cents" => "250"}) == :ok

    assert ReceivedPayment.validate(Map.delete(ok, "idempotency_key")) ==
             {:error, :idempotency_key_required}

    assert ReceivedPayment.validate(%{ok | "payment_method" => "crypto"}) ==
             {:error, :invalid_payment_method}

    for amount <- [0, -5, "x", nil, 1.5] do
      assert ReceivedPayment.validate(%{ok | "amount_cents" => amount}) ==
               {:error, :invalid_payment_amount}
    end
  end

  test "a new document needs a package or a description" do
    assert ReceivedPayment.validate_purpose(:receipt, %{}) == {:error, :payment_purpose_required}

    assert ReceivedPayment.validate_purpose(:invoice, %{"description" => "  "}) ==
             {:error, :payment_purpose_required}

    assert ReceivedPayment.validate_purpose(:invoice, %{"description" => "Water"}) == :ok

    assert ReceivedPayment.validate_purpose(:receipt, %{
             "membership_package_subscription_id" => "sub-1"
           }) == :ok

    assert ReceivedPayment.validate_purpose(:settle_invoice, %{}) == :ok
  end
end
