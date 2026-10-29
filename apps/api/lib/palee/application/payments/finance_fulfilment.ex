defmodule Palee.Application.Payments.FinanceFulfilment do
  @moduledoc """
  ADR-246/248: what a succeeded online payment pays for. An invoice payment
  is recorded in Finance as an `"online"` payment (idempotent per intent);
  a package bought online is assigned with its document; a shop order is
  settled. A refund is a Finance reversal (idempotent per refund).

  ADR-262: recording the money issues its fiscal document;
  `fiscal_document_id` is empty only while the business has no complete
  fiscal identity.
  """

  @behaviour Palee.Payments.Ports.Fulfilment

  alias Palee.Application.Fiscal.PaymentDocuments
  alias Palee.Application.Payments.{OnlineSales, TerminalFulfilment}
  alias Palee.Application.ReceiveFinancePayment
  alias Palee.Finance
  alias Palee.Organizations

  @impl true
  # ADR-249: a card tapped at the desk (method card_terminal).
  def fulfil(context, %{initiation: "terminal"} = intent),
    do: TerminalFulfilment.fulfil(context, intent)

  def fulfil(context, %{purpose_type: "finance_invoice"} = intent) do
    with {:ok, invoice} <- Finance.get_invoice(context, intent.purpose_id),
         {:ok, received} <-
           ReceiveFinancePayment.record_online(context, invoice.user_id, %{
             "finance_invoice_id" => invoice.id,
             "amount_cents" => intent.amount_cents,
             "currency" => intent.currency,
             "paid_on" =>
               context.organization_id
               |> Organizations.local_today(intent.succeeded_at || DateTime.utc_now())
               |> Date.to_iso8601(),
             "idempotency_key" => "payment-intent:" <> intent.id,
             "payment_intent_id" => intent.id,
             "provider" => intent.provider,
             "provider_transaction_id" => intent.provider_transaction_id
           }) do
      {:ok, fulfilled(received)}
    end
  end

  # ADR-248: a package bought online, then the class asked for.
  def fulfil(context, %{purpose_type: "membership_package"} = intent),
    do: OnlineSales.fulfil_package(context, intent, &ReceiveFinancePayment.record_online/3)

  def fulfil(context, %{purpose_type: "shop_order"} = intent),
    do: OnlineSales.fulfil_shop_order(context, intent)

  def fulfil(_context, intent), do: {:error, {:purpose_not_supported, intent.purpose_type}}

  @doc false
  def fulfilled(received) do
    %{
      finance_payment_id: received.payment.id,
      fiscal_document_id: received[:fiscal_document] && received.fiscal_document.id
    }
  end

  @impl true
  def reverse(_context, %{finance_payment_id: nil}, _refund), do: {:ok, %{}}

  def reverse(context, %{initiation: "terminal"} = intent, refund),
    do: TerminalFulfilment.reverse(context, intent, refund)

  def reverse(context, %{purpose_type: "finance_invoice"} = intent, refund) do
    with {:ok, invoice} <- Finance.get_invoice(context, intent.purpose_id) do
      reverse_finance(context, invoice.membership_id, intent, refund)
    end
  end

  def reverse(context, %{purpose_type: "membership_package"} = intent, refund) do
    with {:ok, facts} <- Finance.withdrawal_facts(context, intent.finance_payment_id) do
      reverse_finance(context, facts.membership_id, intent, refund)
    end
  end

  # Shop refunds are recorded on the order by the shop's own refund flow.
  def reverse(_context, _intent, _refund), do: {:ok, %{}}

  defp reverse_finance(context, membership_id, intent, refund) do
    with {:ok, reversal} <-
           Finance.reverse_payment(context, membership_id, intent.finance_payment_id, %{
             "amount_cents" => refund.amount_cents,
             "reversal_type" => "refund",
             "request_id" => refund.id,
             "reason" => refund.reason || "online refund",
             "created_by_id" => refund.created_by_id
           }),
         # ADR-262: a failed credit note fails the refund step, so it retries.
         {:ok, note} <-
           PaymentDocuments.credit(
             context,
             intent.finance_payment_id,
             %{id: reversal_id(reversal), amount_cents: refund.amount_cents},
             refund.created_by_id,
             DateTime.utc_now()
           ) do
      {:ok,
       %{
         finance_reversal_id: reversal_id(reversal),
         fiscal_document_id: if(is_map(note), do: note.id)
       }}
    end
  end

  defp reversal_id(%{reversal: %{id: id}}), do: id
  defp reversal_id(%{id: id}), do: id
  defp reversal_id(_other), do: nil
end
