defmodule Palee.Payments.Domain.IntentPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.IntentPolicy

  @now ~U[2027-02-04 10:00:00.000000Z]

  defp request(changes \\ %{}) do
    Map.merge(
      %{
        purpose_type: "finance_invoice",
        purpose_id: Ecto.UUID.generate(),
        amount_cents: 5_000,
        currency: "EUR",
        idempotency_key: "key-12345"
      },
      changes
    )
  end

  defp intent(changes \\ %{}) do
    Map.merge(
      %{
        amount_cents: 5_000,
        currency: "EUR",
        attempts: 0,
        consent: %{"declines" => 0},
        payment_method_id: Ecto.UUID.generate(),
        inserted_at: @now,
        expires_at: DateTime.add(@now, 3_600, :second),
        fulfilment_attempts: 0,
        refunded_cents: 0,
        status: "scheduled"
      },
      changes
    )
  end

  test "a new intent needs a purpose, a sane amount, a supported currency and a key" do
    assert IntentPolicy.validate_new(request()) == :ok

    assert IntentPolicy.validate_new(request(%{purpose_type: "x"})) ==
             {:error, :invalid_payment_purpose}

    assert IntentPolicy.validate_new(request(%{amount_cents: 0})) ==
             {:error, :invalid_payment_amount}

    assert IntentPolicy.validate_new(request(%{amount_cents: 10_000_001})) ==
             {:error, :invalid_payment_amount}

    assert IntentPolicy.validate_new(request(%{currency: "JPY"})) ==
             {:error, :unsupported_currency}

    assert IntentPolicy.validate_new(request(%{idempotency_key: "short"})) ==
             {:error, :idempotency_key_required}
  end

  test "descriptions lose control characters and stay short" do
    assert IntentPolicy.description("  Τιμολόγιο\n42 ") == "Τιμολόγιο 42"
    assert String.length(IntentPolicy.description(String.duplicate("a", 300))) == 120
    assert IntentPolicy.description(nil) == "Payment"
  end

  test "a paid checkout succeeds and waits to be fulfilled" do
    changes =
      IntentPolicy.checkout_outcome(
        intent(%{status: "awaiting_payer"}),
        {:ok, %{status: :succeeded, transaction_id: "t1", card: %{brand: "visa", last4: "4242"}}},
        @now
      )

    assert changes.status == "succeeded"
    assert changes.fulfilment_status == "pending"
    assert changes.card_last4 == "4242"
    assert changes.next_attempt_at == nil
  end

  test "an unpaid checkout is polled on a backoff and expires after its deadline" do
    waiting = IntentPolicy.checkout_outcome(intent(), {:ok, %{status: :pending}}, @now)
    assert waiting.next_attempt_at == DateTime.add(@now, 120, :second)
    refute Map.has_key?(waiting, :status)

    later = DateTime.add(@now, 4_000, :second)

    assert %{status: "expired"} =
             IntentPolicy.checkout_outcome(intent(), {:ok, %{status: :pending}}, later)

    # An outage after expiry is not proof the payer did not pay: look again.
    outage = IntentPolicy.checkout_outcome(intent(), {:error, {:transient, :timeout}}, later)
    refute Map.has_key?(outage, :status)
  end

  test "a declined saved card is retried 1, 3 and 7 days after the first try, then fails" do
    declined = {:error, {:declined, "51", "Insufficient funds"}}

    first = IntentPolicy.charge_outcome(intent(), declined, @now)
    assert first.status == "scheduled"
    assert first.next_attempt_at == DateTime.add(@now, 86_400, :second)
    assert first.consent["declines"] == 1

    third = IntentPolicy.charge_outcome(intent(%{consent: %{"declines" => 2}}), declined, @now)
    assert third.next_attempt_at == DateTime.add(@now, 7 * 86_400, :second)

    last = IntentPolicy.charge_outcome(intent(%{consent: %{"declines" => 3}}), declined, @now)
    assert last.status == "failed"
    assert last.failure_code == "51"
  end

  test "a charge that may have reached the provider is never sent again by itself" do
    assert %{status: "failed"} =
             IntentPolicy.charge_outcome(intent(), {:error, {:uncertain, "timeout"}}, @now)

    assert %{status: "failed"} =
             IntentPolicy.charge_outcome(intent(), {:error, {:unauthorized, :oauth}}, @now)

    outage = IntentPolicy.charge_outcome(intent(), {:error, {:transient, :econnrefused}}, @now)
    assert outage.status == "scheduled"
    assert outage.next_attempt_at == DateTime.add(@now, 5 * 60, :second)

    assert %{status: "failed"} =
             IntentPolicy.charge_outcome(intent(%{attempts: 4}), {:error, {:transient, :x}}, @now)
  end

  test "a different amount or currency from the provider is a mismatch" do
    refute IntentPolicy.amount_mismatch?(intent(), %{amount_cents: 5_000, currency: "eur"})
    assert IntentPolicy.amount_mismatch?(intent(), %{amount_cents: 4_999, currency: "EUR"})
    assert IntentPolicy.amount_mismatch?(intent(), %{amount_cents: 5_000, currency: "GBP"})
    refute IntentPolicy.amount_mismatch?(intent(), %{amount_cents: nil})
  end

  test "fulfilment backs off and gives up after its last try" do
    done = IntentPolicy.fulfilment_outcome(intent(), {:ok, %{finance_payment_id: "p"}}, @now)
    assert done.fulfilment_status == "done"
    assert done.finance_payment_id == "p"

    retry = IntentPolicy.fulfilment_outcome(intent(), {:error, :boom}, @now)
    assert retry.fulfilment_status == "pending"
    assert retry.next_attempt_at == DateTime.add(@now, 60, :second)

    final =
      IntentPolicy.fulfilment_outcome(intent(%{fulfilment_attempts: 11}), {:error, :boom}, @now)

    assert final.fulfilment_status == "failed"
  end

  test "refunds stay within what is left of a succeeded payment" do
    paid = intent(%{status: "succeeded", refunded_cents: 1_000})
    assert IntentPolicy.validate_refund(paid, 4_000) == :ok
    assert IntentPolicy.validate_refund(paid, 4_001) == {:error, :refund_exceeds_payment}
    assert IntentPolicy.validate_refund(paid, 0) == {:error, :invalid_refund_amount}
    assert IntentPolicy.validate_refund(intent(), 100) == {:error, :payment_not_refundable}
  end
end
