defmodule Palee.Payments.Domain.TerminalPolicyTest do
  @moduledoc "ADR-249: the pure rules of a card tapped at the desk."
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.TerminalPolicy

  @key :crypto.strong_rand_bytes(32)
  @now ~U[2027-02-06 10:00:00.000000Z]

  defp intent(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        organization_id: Ecto.UUID.generate(),
        amount_cents: 4_500,
        currency: "EUR",
        status: "awaiting_payer",
        provider_transaction_id: nil,
        attempts: 0,
        inserted_at: @now,
        expires_at: DateTime.add(@now, 900, :second)
      },
      attrs
    )
  end

  defp request(attrs) do
    Map.merge(
      %{
        purpose_type: "free_sale",
        purpose_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        amount_cents: 1_000,
        currency: "EUR",
        idempotency_key: "desk-key-1"
      },
      attrs
    )
  end

  describe "validate_new/1" do
    test "accepts the desk purposes" do
      for purpose <- ~w(finance_invoice membership_package shop_order free_sale) do
        assert TerminalPolicy.validate_new(request(%{purpose_type: purpose})) == :ok
      end
    end

    test "refuses other purposes, bad money and a missing member" do
      assert TerminalPolicy.validate_new(request(%{purpose_type: "booking"})) ==
               {:error, :invalid_payment_purpose}

      assert TerminalPolicy.validate_new(request(%{amount_cents: 0})) ==
               {:error, :invalid_payment_amount}

      assert TerminalPolicy.validate_new(request(%{currency: "JPY"})) ==
               {:error, :unsupported_currency}

      assert TerminalPolicy.validate_new(request(%{idempotency_key: "short"})) ==
               {:error, :idempotency_key_required}

      assert TerminalPolicy.validate_new(
               request(%{user_id: nil, purpose_type: "finance_invoice"})
             ) ==
               {:error, :terminal_member_required}

      assert TerminalPolicy.validate_new(
               request(%{user_id: nil, purpose_type: "membership_package"})
             ) == {:error, :terminal_member_required}

      # A walk-in may pay a shop order and (ADR-264) a free sale.
      assert TerminalPolicy.validate_new(request(%{user_id: nil, purpose_type: "shop_order"})) ==
               :ok

      assert TerminalPolicy.validate_new(request(%{user_id: nil, purpose_type: "free_sale"})) ==
               :ok

      assert TerminalPolicy.walk_in_purposes() == ~w(shop_order free_sale)
    end
  end

  describe "reference" do
    test "names its intent and is bound to its business, amount and currency" do
      intent = intent()
      reference = TerminalPolicy.reference(intent, @key)

      assert "pt1." <> _rest = reference
      assert TerminalPolicy.reference_intent_id(reference) == {:ok, intent.id}
      assert TerminalPolicy.valid_reference?(reference, intent, @key)

      refute TerminalPolicy.valid_reference?(reference, %{intent | amount_cents: 1}, @key)
      refute TerminalPolicy.valid_reference?(reference, %{intent | currency: "GBP"}, @key)

      refute TerminalPolicy.valid_reference?(
               reference,
               %{intent | organization_id: Ecto.UUID.generate()},
               @key
             )

      refute TerminalPolicy.valid_reference?(reference, intent, :crypto.strong_rand_bytes(32))
      refute TerminalPolicy.valid_reference?(nil, intent, @key)
      assert TerminalPolicy.reference_intent_id("pt1.not-a-uuid.sig") == :error
      assert TerminalPolicy.reference_intent_id("other") == :error
    end

    test "a request may be launched only while open, without a transaction, before it expires" do
      assert TerminalPolicy.launchable?(intent(), @now)
      refute TerminalPolicy.launchable?(intent(), DateTime.add(@now, 900, :second))
      refute TerminalPolicy.launchable?(intent(%{provider_transaction_id: "t"}), @now)
      refute TerminalPolicy.launchable?(intent(%{status: "succeeded"}), @now)
    end
  end

  describe "device results" do
    test "are normalized" do
      assert %{status: :success, transaction_id: "a1", message: "Transaction successful"} =
               TerminalPolicy.device_result(%{
                 status: "success",
                 transaction_id: " a1 ",
                 message: "Transaction successful"
               })

      assert %{status: :fail} = TerminalPolicy.device_result(%{status: "fail"})
      assert %{status: :cancelled} = TerminalPolicy.device_result(%{status: "cancelled"})
      assert %{status: :error, transaction_id: nil} = TerminalPolicy.device_result(%{})
    end

    test "a transaction is confirmed with the provider, never taken from the phone" do
      device = TerminalPolicy.device_result(%{status: "success", transaction_id: "tx-1"})

      assert {:confirm, changes} = TerminalPolicy.apply_device(intent(), device, @now)
      assert changes.provider_transaction_id == "tx-1"
      assert changes.status == "awaiting_payer"
      assert changes.next_attempt_at == @now
      refute Map.has_key?(changes, :succeeded_at)

      # A declined sale with a transaction is confirmed too.
      declined = TerminalPolicy.device_result(%{status: "fail", transaction_id: "tx-2"})
      assert {:confirm, _changes} = TerminalPolicy.apply_device(intent(), declined, @now)
    end

    test "a failure or cancel without a transaction closes the request" do
      for {status, closed, code} <- [
            {"cancelled", "cancelled", "terminal_cancelled"},
            {"fail", "failed", "terminal_declined"},
            {"success", "failed", "terminal_no_transaction"},
            {"weird", "failed", "terminal_app_error"}
          ] do
        device = TerminalPolicy.device_result(%{status: status})
        assert {:close, changes} = TerminalPolicy.apply_device(intent(), device, @now)
        assert changes.status == closed
        assert changes.failure_code == code
        assert changes.next_attempt_at == nil
      end
    end

    test "duplicates change nothing; another transaction for a used request is refused" do
      device = TerminalPolicy.device_result(%{status: "success", transaction_id: "tx-1"})
      paid = intent(%{status: "succeeded", provider_transaction_id: "tx-1"})

      assert TerminalPolicy.apply_device(paid, device, @now) == :unchanged

      other = TerminalPolicy.device_result(%{status: "success", transaction_id: "tx-9"})
      assert TerminalPolicy.apply_device(paid, other, @now) == {:error, :terminal_request_used}

      pending = intent(%{provider_transaction_id: "tx-1"})
      assert TerminalPolicy.apply_device(pending, other, @now) == {:error, :terminal_request_used}

      # A late failure after the transaction is known changes nothing.
      late = TerminalPolicy.device_result(%{status: "fail"})
      assert TerminalPolicy.apply_device(paid, late, @now) == :unchanged
    end

    test "a transaction after a reported cancel reopens the request: money taken is recorded" do
      cancelled = intent(%{status: "cancelled", failure_code: "terminal_cancelled"})
      device = TerminalPolicy.device_result(%{status: "success", transaction_id: "tx-3"})

      assert {:confirm, %{status: "awaiting_payer", provider_transaction_id: "tx-3"}} =
               TerminalPolicy.apply_device(cancelled, device, @now)
    end
  end

  describe "confirm_outcome/4" do
    setup do
      intent = intent(%{provider_transaction_id: "tx-1"})
      %{intent: intent, reference: TerminalPolicy.reference(intent, @key)}
    end

    test "a finished transaction for the amount and reference is paid", ctx do
      transaction = %{
        status: :succeeded,
        transaction_id: "tx-1",
        amount_cents: 4_500,
        currency: "EUR",
        reference: ctx.reference,
        created_at: DateTime.add(@now, 60, :second),
        card: %{brand: "VISA", last4: "1234"}
      }

      changes =
        TerminalPolicy.confirm_outcome(ctx.intent, {:ok, transaction}, ctx.reference, @now)

      assert changes.status == "succeeded"
      assert changes.provider_ref == "tx-1"
      assert changes.fulfilment_status == "pending"
      assert changes.card_last4 == "1234"
      assert changes.succeeded_at == @now
    end

    test "another amount, currency, reference or an older transaction is never paid", ctx do
      base = %{
        status: :succeeded,
        transaction_id: "tx-1",
        amount_cents: 4_500,
        currency: "EUR",
        reference: ctx.reference
      }

      for {change, code} <- [
            {%{amount_cents: 4_700}, "amount_mismatch"},
            {%{currency: "GBP"}, "amount_mismatch"},
            {%{reference: "pt1.someone-else"}, "reference_mismatch"},
            {%{created_at: DateTime.add(@now, -3_600, :second)}, "transaction_before_request"}
          ] do
        changes =
          TerminalPolicy.confirm_outcome(
            ctx.intent,
            {:ok, Map.merge(base, change)},
            ctx.reference,
            @now
          )

        assert changes.status == "failed"
        assert changes.failure_code == code
      end

      # A provider that does not report the reference is judged on the rest.
      changes =
        TerminalPolicy.confirm_outcome(
          ctx.intent,
          {:ok, Map.delete(base, :reference)},
          ctx.reference,
          @now
        )

      assert changes.status == "succeeded"
    end

    test "declined and cancelled at the provider", ctx do
      declined = %{status: :failed, transaction_id: "tx-1", failure: %{code: "viva_E"}}

      assert %{status: "failed", failure_code: "viva_E"} =
               TerminalPolicy.confirm_outcome(ctx.intent, {:ok, declined}, ctx.reference, @now)

      assert %{status: "cancelled", failure_code: "terminal_cancelled"} =
               TerminalPolicy.confirm_outcome(
                 ctx.intent,
                 {:ok, %{status: :cancelled, transaction_id: "tx-1"}},
                 ctx.reference,
                 @now
               )
    end

    test "unconfirmed stays open on the schedule, then waits for staff", ctx do
      changes =
        TerminalPolicy.confirm_outcome(
          ctx.intent,
          {:error, {:transient, :timeout}},
          ctx.reference,
          @now
        )

      assert changes.status == "awaiting_payer"
      assert changes.failure_code == "terminal_unconfirmed"
      assert changes.next_attempt_at == DateTime.add(@now, 30, :second)
      assert changes.attempts == 1

      last = %{ctx.intent | attempts: length(TerminalPolicy.poll_schedule())}

      assert %{status: "awaiting_payer", next_attempt_at: nil} =
               TerminalPolicy.confirm_outcome(
                 last,
                 {:ok, %{status: :pending, transaction_id: "tx-1"}},
                 ctx.reference,
                 @now
               )
    end
  end

  describe "ADR-264: tips and card surcharges" do
    setup do
      intent = intent(%{provider_transaction_id: "tx-1"})

      %{
        intent: intent,
        reference: TerminalPolicy.reference(intent, @key),
        paid: %{status: :succeeded, transaction_id: "tx-1", currency: "EUR"}
      }
    end

    test "split/2 takes the tip and surcharge out of what the card paid", ctx do
      assert TerminalPolicy.split(ctx.intent, %{amount_cents: 4_500}) ==
               {:ok, %{tip_cents: 0, surcharge_cents: 0}}

      assert TerminalPolicy.split(ctx.intent, %{amount_cents: 5_000, tip_cents: 500}) ==
               {:ok, %{tip_cents: 500, surcharge_cents: 0}}

      assert TerminalPolicy.split(ctx.intent, %{
               amount_cents: 4_635,
               tip_cents: nil,
               surcharge_cents: 135
             }) == {:ok, %{tip_cents: 0, surcharge_cents: 135}}

      assert TerminalPolicy.split(ctx.intent, %{
               amount_cents: 5_135,
               tip_cents: 500,
               surcharge_cents: 135,
               currency: "eur"
             }) == {:ok, %{tip_cents: 500, surcharge_cents: 135}}

      # Anything else the card paid is never accepted.
      for transaction <- [
            %{amount_cents: 5_000},
            %{amount_cents: 4_000},
            %{amount_cents: 5_000, tip_cents: 400},
            %{amount_cents: 4_500, tip_cents: 500},
            %{amount_cents: 4_400, tip_cents: -100},
            %{amount_cents: 4_600, surcharge_cents: "100"},
            %{amount_cents: 5_000, tip_cents: 500, currency: "GBP"}
          ] do
        assert TerminalPolicy.split(ctx.intent, transaction) == {:error, "amount_mismatch"}
      end
    end

    test "a tip and a surcharge on top of the amount succeed and are kept apart", ctx do
      transaction =
        Map.merge(ctx.paid, %{
          amount_cents: 5_135,
          tip_cents: 500,
          surcharge_cents: 135,
          reference: ctx.reference
        })

      changes =
        TerminalPolicy.confirm_outcome(ctx.intent, {:ok, transaction}, ctx.reference, @now)

      assert changes.status == "succeeded"
      assert changes.tip_cents == 500
      assert changes.surcharge_cents == 135
      assert changes.fulfilment_status == "pending"
    end

    test "a plain sale records no tip or surcharge", ctx do
      changes =
        TerminalPolicy.confirm_outcome(
          ctx.intent,
          {:ok, Map.put(ctx.paid, :amount_cents, 4_500)},
          ctx.reference,
          @now
        )

      assert %{status: "succeeded", tip_cents: 0, surcharge_cents: 0} = changes
    end

    test "any other difference still fails", ctx do
      changes =
        TerminalPolicy.confirm_outcome(
          ctx.intent,
          {:ok, Map.merge(ctx.paid, %{amount_cents: 5_200, tip_cents: 500})},
          ctx.reference,
          @now
        )

      assert changes.status == "failed"
      assert changes.failure_code == "amount_mismatch"
      refute Map.has_key?(changes, :tip_cents)
    end
  end

  describe "a result that never came" do
    test "is looked for after expiry, then the request expires" do
      intent = intent()
      assert TerminalPolicy.too_early_to_look?(intent, @now)
      refute TerminalPolicy.too_early_to_look?(intent, DateTime.add(@now, 961, :second))

      assert %{next_attempt_at: at} = TerminalPolicy.lost_outcome(intent, {:ok, nil}, @now)
      assert at == DateTime.add(@now, 30, :second)

      done = %{intent | attempts: length(TerminalPolicy.poll_schedule())}

      assert %{status: "expired", failure_code: "terminal_no_result"} =
               TerminalPolicy.lost_outcome(done, {:ok, nil}, @now)
    end
  end
end
