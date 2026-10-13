defmodule MilosTraining.Finance.Domain.ReconciliationMatchingTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.ReconciliationMatching

  defp line(overrides \\ %{}) do
    {:ok, line} =
      %{
        "provider" => " Stripe ",
        "external_reference" => " ch_123 ",
        "external_type" => "payment",
        "statement_amount_cents" => "5000",
        "statement_currency" => "eur",
        "statement_occurred_on" => "2026-10-10"
      }
      |> Map.merge(overrides)
      |> ReconciliationMatching.normalize_statement_line()

    line
  end

  defp payment(overrides \\ %{}) do
    Map.merge(
      %{
        id: "pay-1",
        kind: :payment,
        amount_cents: 5_000,
        currency: "EUR",
        occurred_on: ~D[2026-10-09],
        status: "paid"
      },
      overrides
    )
  end

  describe "normalize_statement_line/1" do
    test "normalizes provider, reference, currency, amount and date" do
      assert %{
               provider: "stripe",
               external_reference: "ch_123",
               external_type: "payment",
               external_status: "settled",
               statement_amount_cents: 5_000,
               statement_currency: "EUR",
               statement_occurred_on: ~D[2026-10-10],
               statement_description: nil
             } = line()
    end

    test "collects every invalid field" do
      assert {:error, errors} =
               ReconciliationMatching.normalize_statement_line(%{
                 "provider" => "Bad Provider!",
                 "external_reference" => "",
                 "external_type" => "chargeback",
                 "external_status" => "unknown",
                 "statement_amount_cents" => -5,
                 "statement_currency" => "euro",
                 "statement_occurred_on" => "10/10/2026"
               })

      assert Keyword.keys(errors) == [
               :provider,
               :external_reference,
               :external_type,
               :external_status,
               :statement_amount_cents,
               :statement_currency,
               :statement_occurred_on
             ]
    end
  end

  describe "evaluate/2" do
    test "an exact payment within the date tolerance matches" do
      assert ReconciliationMatching.evaluate(line(), payment()) ==
               %{status: "matched", discrepancies: []}
    end

    test "flags amount, currency, date, settlement and type discrepancies" do
      result =
        ReconciliationMatching.evaluate(
          line(%{"external_status" => "pending"}),
          payment(%{
            kind: :reversal,
            amount_cents: 4_000,
            currency: "USD",
            occurred_on: ~D[2026-10-01]
          })
        )

      assert result.status == "mismatched"

      assert result.discrepancies == [
               "type_mismatch",
               "amount_mismatch",
               "currency_mismatch",
               "date_out_of_tolerance",
               "provider_not_settled"
             ]
    end

    test "a pending internal payment is not settled" do
      assert %{status: "mismatched", discrepancies: ["internal_not_settled"]} =
               ReconciliationMatching.evaluate(line(), payment(%{status: "pending"}))
    end

    test "a refund line reconciles against a reversal" do
      refund = line(%{"external_type" => "refund", "statement_amount_cents" => 2_000})

      assert %{status: "matched"} =
               ReconciliationMatching.evaluate(
                 refund,
                 %{
                   kind: :reversal,
                   amount_cents: 2_000,
                   currency: "EUR",
                   occurred_on: ~D[2026-10-11]
                 }
               )
    end
  end

  test "detects conflicting replays of the same external reference" do
    existing = line()
    refute ReconciliationMatching.replay_conflict?(existing, line())

    assert ReconciliationMatching.replay_conflict?(
             existing,
             line(%{"statement_amount_cents" => 1})
           )
  end

  test "ranks exact amounts first and excludes other kinds and currencies" do
    facts = [
      payment(%{id: "near-date-wrong-amount", amount_cents: 4_900, occurred_on: ~D[2026-10-10]}),
      payment(%{id: "exact", occurred_on: ~D[2026-10-08]}),
      payment(%{id: "usd", currency: "USD"}),
      payment(%{id: "reversal", kind: :reversal}),
      payment(%{id: "far", amount_cents: 1_000, occurred_on: ~D[2026-08-01]})
    ]

    assert [first, second] = ReconciliationMatching.rank_candidates(line(), facts)
    assert first.id == "exact"
    assert first.evaluation.status == "matched"
    assert second.id == "near-date-wrong-amount"
    assert second.evaluation.discrepancies == ["amount_mismatch"]
  end

  test "parses target types" do
    assert ReconciliationMatching.parse_target_type("payment") == {:ok, :payment}
    assert ReconciliationMatching.parse_target_type("reversal") == {:ok, :reversal}

    assert ReconciliationMatching.parse_target_type("invoice") ==
             {:error, :invalid_reconciliation_target}
  end
end
