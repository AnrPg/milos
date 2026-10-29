defmodule Palee.Application.Payments.TerminalFulfilment do
  @moduledoc """
  ADR-249: what a card tapped at the desk pays for, once the provider
  confirmed it. Membership money goes through ADR-222's
  `Finance.receive_payment` with the method `card_terminal` (the box's
  billing setup picks the document), idempotent per intent; a shop order
  is settled by the shop. Refunds are Finance reversals, as for online
  payments.
  """

  alias Palee.Application.Payments.OnlineSales
  alias Palee.Application.ReceiveFinancePayment
  alias Palee.Application.Shop.Checkout
  alias Palee.Finance
  alias Palee.Organizations

  def fulfil(context, %{purpose_type: "finance_invoice"} = intent) do
    with {:ok, invoice} <- Finance.get_invoice(context, intent.purpose_id) do
      record(context, invoice.user_id, intent, %{"finance_invoice_id" => invoice.id})
    end
  end

  # A πακέτο συνδρομής sold at the desk: assigned with its money (ADR-248).
  def fulfil(context, %{purpose_type: "membership_package"} = intent) do
    OnlineSales.fulfil_package(context, intent, fn context, user_id, params ->
      ReceiveFinancePayment.record_terminal(
        context,
        user_id,
        Map.merge(params, terminal_params(intent))
      )
    end)
  end

  def fulfil(context, %{purpose_type: "free_sale"} = intent) do
    record(context, intent.user_id, intent, %{
      "description" => intent.description,
      "charge_category" => (intent.metadata || %{})["charge_category"]
    })
  end

  def fulfil(context, %{purpose_type: "shop_order"} = intent) do
    with {:ok, order} <-
           Checkout.settle_at_terminal(context, intent.purpose_id, %{
             provider: intent.provider,
             reference: intent.provider_transaction_id,
             idempotency_key: "terminal:" <> intent.id
           }) do
      {:ok, %{finance_payment_id: order[:finance_payment_id]}}
    end
  end

  def fulfil(_context, intent), do: {:error, {:purpose_not_supported, intent.purpose_type}}

  defp record(context, user_id, intent, purpose) do
    params =
      %{
        "amount_cents" => intent.amount_cents,
        "currency" => intent.currency,
        "paid_on" => paid_on(context, intent),
        "idempotency_key" => "payment-intent:" <> intent.id
      }
      |> Map.merge(terminal_params(intent))
      |> Map.merge(Map.reject(purpose, fn {_key, value} -> is_nil(value) end))

    with {:ok, received} <- ReceiveFinancePayment.record_terminal(context, user_id, params) do
      {:ok, %{finance_payment_id: received.payment.id}}
    end
  end

  defp terminal_params(intent) do
    %{
      "payment_intent_id" => intent.id,
      "provider" => intent.provider,
      "provider_transaction_id" => intent.provider_transaction_id,
      "created_by_id" => intent.created_by_id
    }
  end

  defp paid_on(context, intent) do
    context.organization_id
    |> Organizations.local_today(intent.succeeded_at || DateTime.utc_now())
    |> Date.to_iso8601()
  end

  @doc "Money given back for a terminal payment: a Finance reversal (the shop records its own)."
  def reverse(_context, %{finance_payment_id: nil}, _refund), do: {:ok, %{}}
  def reverse(_context, %{purpose_type: "shop_order"}, _refund), do: {:ok, %{}}

  def reverse(context, intent, refund) do
    with %{membership: %{id: membership_id}} <-
           Finance.get_member_profile(context, intent.user_id) || {:error, :not_found},
         {:ok, reversal} <-
           Finance.reverse_payment(context, membership_id, intent.finance_payment_id, %{
             "amount_cents" => refund.amount_cents,
             "reversal_type" => "refund",
             "request_id" => refund.id,
             "reason" => refund.reason || "terminal refund",
             "created_by_id" => refund.created_by_id
           }) do
      {:ok, %{finance_reversal_id: reversal_id(reversal)}}
    end
  end

  defp reversal_id(%{reversal: %{id: id}}), do: id
  defp reversal_id(%{id: id}), do: id
  defp reversal_id(_other), do: nil
end
