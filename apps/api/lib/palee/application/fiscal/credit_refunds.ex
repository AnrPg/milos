defmodule Palee.Application.Fiscal.CreditRefunds do
  @moduledoc """
  The credit-note panel's «refund to the card» switch (ADR-265, mockup s2):
  a document paid online or at the terminal can be credited **and** its
  money given back in one action.

  The refund issues the credit note, as every refund does (ADR-262), so one
  action never makes two notes:

    1. the note the request would issue is computed first
       (`Fiscal.credit_preview/4`) and exactly its gross is refunded;
    2. the refund carries `fiscal_credit` (the reason and, for a partial
       note, the chosen lines); `PaymentDocuments.credit/5` issues the note
       from it when the fulfilment reverses the Finance payment;
    3. the answer is the note the refund issued (`finance-reversal:<id>`).

  Idempotent by the panel's key: the refund's key is `fiscal-credit:<key>`,
  so a repeated click returns the same refund and note.
  """

  alias Palee.{Fiscal, Payments}

  @doc """
  What the panel shows for `document`: `%{provider, card_brand, card_last4,
  refundable_cents}` when it was paid online or at the terminal and money
  is left to give back; otherwise nil.
  """
  def option(context, %{kind: kind, source_type: "finance_payment", source_id: payment_id})
      when kind in ["receipt", "invoice"] and is_binary(payment_id) do
    case Payments.succeeded_for_finance_payment(context, payment_id) do
      %{amount_cents: amount} = intent ->
        left = amount - (intent[:refunded_cents] || 0)

        if left > 0 do
          %{
            provider: intent.provider,
            card_brand: intent[:card_brand],
            card_last4: intent[:card_last4],
            refundable_cents: left
          }
        end

      nil ->
        nil
    end
  end

  def option(_context, _document), do: nil

  @doc """
  Refunds what the credit note of `requested` would credit, and lets the
  refund issue that note. `{:ok, %{document: note | nil, refund: refund},
  :issued | :replayed}` or `{:error, reason}` (`:refund_not_available`
  when the document was not paid online or at the terminal).
  """
  def credit_and_refund(context, document_id, request, actor_id, %DateTime{} = now) do
    %{requested: requested, reason: reason, key: key, issue_date: issue_date} = request
    refund_key = "fiscal-credit:" <> key

    case Payments.refund_by_key(context, refund_key) do
      %{} = refund ->
        {:ok, %{document: note_of(context, refund), refund: refund}, :replayed}

      nil ->
        with %{} = document <- Fiscal.get_document(context, document_id) || {:error, :not_found},
             {:ok, reason} <- Fiscal.credit_reason(reason),
             %{} = intent <- intent_for(context, document) || {:error, :refund_not_available},
             {:ok, note} <- Fiscal.credit_preview(context, document.id, requested, issue_date),
             {:ok, refund} <-
               Payments.refund(
                 context,
                 intent.id,
                 %{
                   amount_cents: note.gross_cents,
                   idempotency_key: refund_key,
                   reason: reason,
                   fiscal_credit: fiscal_credit(requested, reason)
                 },
                 actor_id,
                 now
               ) do
          {:ok, %{document: note_of(context, refund), refund: refund}, :issued}
        end
    end
  end

  defp intent_for(context, %{source_type: "finance_payment", source_id: payment_id})
       when is_binary(payment_id),
       do: Payments.succeeded_for_finance_payment(context, payment_id)

  defp intent_for(_context, _document), do: nil

  # Stored as JSON: string keys. A full note credits by amount (all that
  # is left), a partial one exactly the chosen lines.
  defp fiscal_credit(lines, reason) when is_list(lines),
    do: %{
      "reason" => reason,
      "lines" =>
        Enum.map(lines, &%{"position" => &1.position, "quantity" => &1.quantity})
    }

  defp fiscal_credit(_all, reason), do: %{"reason" => reason}

  defp note_of(context, %{finance_reversal_id: id}) when is_binary(id),
    do: Fiscal.document_by_key(context, "finance-reversal:" <> id)

  defp note_of(_context, _refund), do: nil
end
