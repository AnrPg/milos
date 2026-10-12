defmodule MilosTraining.Finance.Domain.RefundReceiptTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.{RefundReceipt, RefundReceiptDocument}

  @issued_at ~U[2026-10-12 09:30:00.000000Z]

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        organization_id: "org-1",
        receipt_number: "RFD-000007",
        sequence: 7,
        issued_at: @issued_at,
        payment_reversed_total_cents: 3_000,
        party: %{organization_name: "Iron Gym", member_display_name: "Alex <Admin>"},
        reversal: %{
          id: "rev-1",
          user_id: "user-1",
          membership_id: "mem-1",
          reversal_type: "refund",
          amount_cents: 2_000,
          currency: "EUR",
          reason: "  Class cancelled  ",
          occurred_on: ~D[2026-10-12],
          occurred_at: @issued_at,
          created_by_id: "admin-1"
        },
        payment: %{
          id: "pay-1",
          amount_cents: 5_000,
          currency: "EUR",
          paid_on: ~D[2026-10-01],
          payment_method: "cash",
          payment_status: "paid"
        },
        invoice: %{
          id: "inv-1",
          invoice_number: "INV-000010-MANUAL-20261001000000",
          total_cents: 5_000,
          currency: "EUR",
          params: %{"document_kind" => "receipt"}
        }
      },
      overrides
    )
  end

  test "money-returning reversals require a receipt; waiver reversals do not" do
    assert RefundReceipt.required?("refund")
    assert RefundReceipt.required?("payment_reversal")
    refute RefundReceipt.required?("waiver_reversal")
  end

  test "the snapshot captures reversal, payment, invoice, parties and running totals" do
    snapshot = RefundReceipt.build_snapshot(attrs())

    assert snapshot["receipt_number"] == "RFD-000007"
    assert snapshot["sequence"] == 7
    assert snapshot["issued_at"] == "2026-10-12T09:30:00.000000Z"
    assert snapshot["organization"] == %{"id" => "org-1", "name" => "Iron Gym"}
    assert snapshot["member"]["display_name"] == "Alex <Admin>"
    assert snapshot["reversal"]["reason"] == "Class cancelled"
    assert snapshot["reversal"]["amount_cents"] == 2_000
    assert snapshot["original_payment"]["paid_on"] == "2026-10-01"
    assert snapshot["invoice"]["document_kind"] == "receipt"

    assert snapshot["totals"] == %{
             "refunded_cents" => 2_000,
             "previously_refunded_cents" => 1_000,
             "remaining_paid_cents" => 2_000
           }
  end

  test "a payment without an invoice snapshots a nil invoice" do
    assert RefundReceipt.build_snapshot(attrs(%{invoice: nil}))["invoice"] == nil
  end

  test "the fingerprint is stable regardless of key order and survives a JSON round trip" do
    snapshot = RefundReceipt.build_snapshot(attrs())
    fingerprint = RefundReceipt.sha256(snapshot)

    round_tripped = snapshot |> Jason.encode!() |> Jason.decode!()
    assert RefundReceipt.sha256(round_tripped) == fingerprint
    assert RefundReceipt.verify(round_tripped, fingerprint)

    refute RefundReceipt.verify(
             put_in(round_tripped, ["totals", "refunded_cents"], 1),
             fingerprint
           )

    assert fingerprint =~ ~r/^[0-9a-f]{64}$/
  end

  test "the document is deterministic, escaped and shows the receipt data" do
    snapshot = RefundReceipt.build_snapshot(attrs())
    labels = Map.new(RefundReceiptDocument.label_keys(), &{&1, "L:#{&1}"})

    html = RefundReceiptDocument.render_html(snapshot, labels, fingerprint: "abc", lang: "el")

    assert html ==
             RefundReceiptDocument.render_html(snapshot, labels, fingerprint: "abc", lang: "el")

    assert html =~ "<html lang=\"el\" dir=\"ltr\">"
    assert html =~ "RFD-000007"
    assert html =~ "Alex &lt;Admin&gt;"
    refute html =~ "Alex <Admin>"
    assert html =~ "20.00 EUR"
    assert html =~ "50.00 EUR"
    assert html =~ "L:type_refund"
    assert html =~ "<code>abc</code>"
    refute html =~ "<script"
  end

  test "missing values fall back to the not-provided label and rtl is honoured" do
    snapshot =
      attrs(%{party: nil, invoice: nil})
      |> RefundReceipt.build_snapshot()
      |> put_in(["reversal", "reason"], nil)

    labels = Map.new(RefundReceiptDocument.label_keys(), &{&1, "L:#{&1}"})
    html = RefundReceiptDocument.render_html(snapshot, labels, dir: "rtl")

    assert html =~ "dir=\"rtl\""
    assert html =~ "<dd>L:not_provided</dd>"
  end

  test "money formatting is locale neutral and exact" do
    assert RefundReceiptDocument.money(5, "EUR") == "0.05 EUR"
    assert RefundReceiptDocument.money(-1_234, "USD") == "-12.34 USD"
    assert RefundReceiptDocument.money(nil, "EUR") == nil
  end
end
