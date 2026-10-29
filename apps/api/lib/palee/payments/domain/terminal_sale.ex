defmodule Palee.Payments.Domain.TerminalSale do
  @moduledoc """
  The Finance rows of money tapped at the desk that has no invoice of its
  own (ADR-264), pure. Like the shop's (ADR-190), every row carries its
  revenue stream and a source, the payment intent, so the money is
  traceable from a Finance total down to the card transaction:

      finance_invoice_line (source_type walk_in_sale | card_surcharge, source_id intent)
      membership_payment   (same source; one live payment per source)
      finance_payment_reversal (inherits the payment's stream and source)

    * `walk_in/3`: a walk-in's free sale (no membership): one line for the
      sale and, when the provider added one, one for the card surcharge;
      paid by one `card_terminal` payment of both.
    * `surcharge/4`: the card surcharge on top of a member's invoice,
      package or free sale, or of a shop order: its own invoice and
      payment (stream `other`), the member's when there is one.

  A tip is in neither: it is the staff's money, not the sale's, and stays
  on the intent and the payment's params for reconciliation.
  """

  @walk_in_source "walk_in_sale"
  @surcharge_source "card_surcharge"

  def walk_in_source, do: @walk_in_source
  def surcharge_source, do: @surcharge_source

  @doc """
  The sale of a walk-in's free sale, for `Finance.record_stream_sale/2`.
  `labels`: `%{surcharge: "Card surcharge"}` (the business's language).
  """
  def walk_in(intent, %Date{} = today, labels) do
    category = charge_category(intent)
    stream = if category == "event", do: "event", else: "other"
    surcharge = intent.surcharge_cents || 0

    sale_line =
      line(intent, @walk_in_source, stream, intent.description, category, intent.amount_cents)

    lines =
      if surcharge > 0,
        do: [
          sale_line,
          line(intent, @surcharge_source, stream, labels.surcharge, category, surcharge)
        ],
        else: [sale_line]

    %{
      "invoice" => invoice(intent, stream, nil, nil, today, lines),
      "payment" =>
        payment(intent, @walk_in_source, stream, nil, intent.amount_cents + surcharge, today)
    }
  end

  @doc """
  The card surcharge of a sale whose money Finance records elsewhere (the
  member's invoice, package or free sale, or a shop order), for
  `Finance.record_stream_sale/2`. `membership` is `%{membership_id,
  user_id}` or nil for a walk-in.
  """
  def surcharge(intent, membership, %Date{} = today, labels) do
    membership = membership || %{}

    line =
      line(intent, @surcharge_source, "other", labels.surcharge, "other", intent.surcharge_cents)

    %{
      "invoice" =>
        invoice(intent, "other", membership[:membership_id], membership[:user_id], today, [line]),
      "payment" =>
        payment(
          intent,
          @surcharge_source,
          "other",
          membership[:membership_id],
          intent.surcharge_cents,
          today
        )
    }
  end

  @doc "Whether the provider added a card surcharge to the intent's sale."
  def surcharge?(intent), do: is_integer(intent.surcharge_cents) and intent.surcharge_cents > 0

  defp invoice(intent, stream, membership_id, user_id, today, lines) do
    %{
      "revenue_stream" => stream,
      "membership_id" => membership_id,
      "user_id" => user_id,
      "invoice_type" => "manual",
      "issue_date" => today,
      "due_date" => today,
      "currency" => intent.currency,
      "notes" => intent.description,
      "params" => params(intent),
      "lines" => lines
    }
  end

  defp line(intent, source, stream, description, category, cents) do
    %{
      "line_type" => "manual_charge",
      "charge_category" => category,
      "revenue_stream" => stream,
      "source_type" => source,
      "source_id" => intent.id,
      "description" => description,
      "quantity" => 1,
      "unit_amount_cents" => cents,
      "discount_cents" => 0,
      "total_cents" => cents,
      "params" => params(intent)
    }
  end

  defp payment(intent, source, stream, membership_id, cents, today) do
    %{
      "revenue_stream" => stream,
      "source_type" => source,
      "source_id" => intent.id,
      "membership_id" => membership_id,
      "amount_cents" => cents,
      "currency" => intent.currency,
      "paid_on" => today,
      "payment_method" => "card_terminal",
      "payment_status" => "paid",
      "notes" => intent.description,
      "params" =>
        Map.merge(params(intent), %{
          "idempotency_key" => "payment-intent:#{source}:" <> intent.id,
          "created_by_id" => intent.created_by_id,
          "tip_cents" => intent.tip_cents || 0,
          "surcharge_cents" => intent.surcharge_cents || 0
        })
    }
  end

  defp params(intent) do
    %{
      "payment_intent_id" => intent.id,
      "provider" => intent.provider,
      "provider_transaction_id" => intent.provider_transaction_id,
      "purpose_type" => intent.purpose_type
    }
  end

  defp charge_category(intent) do
    case intent.metadata do
      %{"charge_category" => category} when is_binary(category) -> category
      _none -> "other"
    end
  end
end
