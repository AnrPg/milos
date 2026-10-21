defmodule Palee.Infrastructure.Finance.FinanceEventPayments do
  @moduledoc """
  Finance adapter of `Application.Ports.EventPayments` (ADR-153): when the
  person has a Finance record at the box, the payment is a receipt there (an
  issued manual invoice paid in full, the same path as «Απόδειξη» in a
  member's finance page), so it shows in their payments, the box's reports
  and its accounting export. People Finance doesn't know (open events,
  guests) have no record to hang a receipt on; their payment stays on the
  event's attendee row only.
  """

  @behaviour Palee.Application.Ports.EventPayments

  alias Palee.Finance

  @impl true
  def record(context, payment) do
    case Finance.get_member_profile(context, payment.user_id) do
      %{membership: %{id: membership_id}} ->
        context
        |> Finance.create_receipt(membership_id, %{
          "amount_cents" => payment.amount_cents,
          "currency" => payment.currency,
          "payment_method" => payment.method,
          "description" => payment.description,
          "notes" => payment.description,
          "created_by_id" => payment.recorded_by_id,
          "idempotency_key" => payment.reference
        })
        |> case do
          {:ok, receipt} ->
            {:ok,
             %{finance_invoice_id: receipt.invoice.id, finance_payment_id: receipt.payment.id}}

          {:error, reason} ->
            {:error, reason}
        end

      _no_finance_record ->
        {:ok, %{finance_invoice_id: nil, finance_payment_id: nil}}
    end
  end
end
