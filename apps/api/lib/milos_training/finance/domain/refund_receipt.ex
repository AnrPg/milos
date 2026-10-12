defmodule MilosTraining.Finance.Domain.RefundReceipt do
  @moduledoc """
  Pure rules for refund receipts (ADR-116).

  A receipt is issued for every payment reversal that returns money
  (`refund`, `payment_reversal`). A `waiver_reversal` cancels a waived
  payment - no money changed hands - so it gets no receipt.

  The snapshot is the immutable accounting record: everything a receipt
  shows, captured at issue time with string keys. `canonical_json/1` encodes
  it with recursively sorted keys so `sha256/1` is stable across the jsonb
  round trip; `verify/2` recomputes it from a stored snapshot.
  """

  @schema_version 1
  @receipt_reversal_types ["refund", "payment_reversal"]

  def schema_version, do: @schema_version

  @doc "Whether a reversal of this type is documented by a refund receipt."
  def required?(reversal_type), do: reversal_type in @receipt_reversal_types

  @doc """
  Builds the snapshot. `attrs` carries plain maps (atom keys) for
  `:reversal`, `:payment`, `:invoice` (or nil), `:party`
  (`%{organization_name, member_display_name}` - optional), plus
  `:receipt_number`, `:sequence`, `:issued_at`, `:organization_id` and
  `:payment_reversed_total_cents` (all reversals of the payment including
  this one).
  """
  def build_snapshot(attrs) do
    reversal = Map.fetch!(attrs, :reversal)
    payment = Map.fetch!(attrs, :payment)
    invoice = Map.get(attrs, :invoice)
    party = Map.get(attrs, :party) || %{}
    total_reversed = Map.fetch!(attrs, :payment_reversed_total_cents)

    %{
      "schema_version" => @schema_version,
      "document_type" => "refund_receipt",
      "receipt_number" => Map.fetch!(attrs, :receipt_number),
      "sequence" => Map.fetch!(attrs, :sequence),
      "issued_at" => iso8601(Map.fetch!(attrs, :issued_at)),
      "organization" => %{
        "id" => Map.fetch!(attrs, :organization_id),
        "name" => text(party_value(party, :organization_name))
      },
      "member" => %{
        "user_id" => reversal.user_id,
        "membership_id" => reversal.membership_id,
        "display_name" => text(party_value(party, :member_display_name))
      },
      "reversal" => %{
        "id" => reversal.id,
        "type" => reversal.reversal_type,
        "amount_cents" => reversal.amount_cents,
        "currency" => reversal.currency,
        "reason" => text(reversal.reason),
        "occurred_on" => iso8601(reversal.occurred_on),
        "occurred_at" => iso8601(reversal.occurred_at),
        "recorded_by_id" => reversal.created_by_id
      },
      "original_payment" => %{
        "id" => payment.id,
        "amount_cents" => payment.amount_cents,
        "currency" => payment.currency,
        "paid_on" => iso8601(payment.paid_on),
        "payment_method" => payment.payment_method,
        "payment_status" => payment.payment_status
      },
      "invoice" => invoice_snapshot(invoice),
      "totals" => %{
        "refunded_cents" => reversal.amount_cents,
        "previously_refunded_cents" => max(total_reversed - reversal.amount_cents, 0),
        "remaining_paid_cents" => max(payment.amount_cents - total_reversed, 0)
      }
    }
  end

  @doc "Deterministic JSON encoding (keys sorted at every level)."
  def canonical_json(term), do: term |> canonical() |> Jason.encode!()

  @doc "Lower-case hex SHA-256 of the canonical snapshot."
  def sha256(snapshot),
    do: :crypto.hash(:sha256, canonical_json(snapshot)) |> Base.encode16(case: :lower)

  @doc "True when a stored snapshot still hashes to the recorded fingerprint."
  def verify(snapshot, fingerprint) when is_map(snapshot) and is_binary(fingerprint),
    do: sha256(snapshot) == fingerprint

  def verify(_snapshot, _fingerprint), do: false

  defp invoice_snapshot(nil), do: nil

  defp invoice_snapshot(invoice) do
    %{
      "id" => invoice.id,
      "invoice_number" => invoice.invoice_number,
      "document_kind" => (Map.get(invoice, :params) || %{})["document_kind"] || "invoice",
      "total_cents" => invoice.total_cents,
      "currency" => invoice.currency
    }
  end

  defp party_value(party, key), do: Map.get(party, key) || Map.get(party, Atom.to_string(key))

  defp text(nil), do: nil

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 500)
    end
  end

  defp text(_value), do: nil

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp iso8601(%Date{} = value), do: Date.to_iso8601(value)
  defp iso8601(value) when is_binary(value), do: value

  defp canonical(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value
end
