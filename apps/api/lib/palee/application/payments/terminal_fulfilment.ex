defmodule Palee.Application.Payments.TerminalFulfilment do
  @moduledoc """
  ADR-249: what a card tapped at the desk pays for, once the provider
  confirmed it. Membership money goes through ADR-222's
  `Finance.receive_payment` with the method `card_terminal` (the box's
  billing setup picks the document), idempotent per intent; a shop order
  is settled by the shop. Refunds are Finance reversals, as for online
  payments. ADR-262: the money issues its fiscal document and a refund
  credits it.

  ADR-264: a walk-in's free sale is a Finance stream sale with no
  membership (`TerminalSale.walk_in/3`) and its receipt. A card surcharge
  the provider added is revenue of the sale: recorded in Finance apart
  (`TerminalSale.surcharge/4`, idempotent per intent) and printed on the
  sale's receipt. A tip is the staff's: kept on the intent and the
  payment, never revenue.
  """

  alias Palee.Application.Fiscal.PaymentDocuments
  alias Palee.Application.Payments.{FinanceFulfilment, OnlineSales}
  alias Palee.Application.ReceiveFinancePayment
  alias Palee.Application.Shop.Checkout
  alias Palee.Finance
  alias Palee.Fiscal
  alias Palee.Organizations
  alias Palee.Payments.Domain.TerminalSale
  alias Palee.Shop

  def fulfil(context, intent) do
    with {:ok, result} <- fulfil_sale(context, intent),
         :ok <- record_surcharge(context, intent) do
      {:ok, result}
    end
  end

  defp fulfil_sale(context, %{purpose_type: "finance_invoice"} = intent) do
    with {:ok, invoice} <- Finance.get_invoice(context, intent.purpose_id) do
      record(context, invoice.user_id, intent, %{"finance_invoice_id" => invoice.id})
    end
  end

  # A πακέτο συνδρομής sold at the desk: assigned with its money (ADR-248).
  defp fulfil_sale(context, %{purpose_type: "membership_package"} = intent) do
    OnlineSales.fulfil_package(context, intent, fn context, user_id, params ->
      ReceiveFinancePayment.record_terminal(
        context,
        user_id,
        params
        |> Map.merge(terminal_params(intent))
        |> Map.merge(surcharge_params(context, intent))
      )
    end)
  end

  # ADR-264: a walk-in's free sale, with no membership.
  defp fulfil_sale(context, %{purpose_type: "free_sale", user_id: nil} = intent) do
    sale = TerminalSale.walk_in(intent, paid_on_date(context, intent), labels(context))

    with {:ok, received} <-
           ReceiveFinancePayment.record_walk_in(context, sale, intent.created_by_id) do
      {:ok, FinanceFulfilment.fulfilled(received)}
    end
  end

  defp fulfil_sale(context, %{purpose_type: "free_sale"} = intent) do
    record(context, intent.user_id, intent, %{
      "description" => intent.description,
      "charge_category" => (intent.metadata || %{})["charge_category"]
    })
  end

  defp fulfil_sale(context, %{purpose_type: "shop_order"} = intent) do
    with {:ok, order} <-
           Checkout.settle_at_terminal(context, intent.purpose_id, %{
             provider: intent.provider,
             reference: intent.provider_transaction_id,
             idempotency_key: "terminal:" <> intent.id
           }) do
      {:ok, %{finance_payment_id: shop_payment_id(context, order)}}
    end
  end

  defp fulfil_sale(_context, intent),
    do: {:error, {:purpose_not_supported, intent.purpose_type}}

  # ADR-264: the card surcharge of a sale whose money is recorded elsewhere
  # (a walk-in's sale has it on its own invoice).
  defp record_surcharge(_context, %{purpose_type: "free_sale", user_id: nil}), do: :ok

  defp record_surcharge(context, intent) do
    if TerminalSale.surcharge?(intent) do
      sale =
        TerminalSale.surcharge(
          intent,
          membership(context, intent.user_id),
          paid_on_date(context, intent),
          labels(context)
        )

      case Finance.record_stream_sale(context, sale) do
        {:ok, _recorded} -> :ok
        {:error, _reason} = error -> error
      end
    else
      :ok
    end
  end

  defp membership(_context, nil), do: nil

  defp membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{id: id}} -> %{membership_id: id, user_id: user_id}
      _none -> nil
    end
  end

  # The surcharge goes on the sale's receipt (shop orders have none in Palee yet).
  defp surcharge_params(context, intent) do
    if TerminalSale.surcharge?(intent),
      do: %{
        "surcharge_cents" => intent.surcharge_cents,
        "surcharge_description" => labels(context).surcharge
      },
      else: %{}
  end

  # Names printed on the business's documents, in its language.
  defp labels(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{country_code: "GR"}} -> %{surcharge: "Επιβάρυνση κάρτας"}
      _other -> %{surcharge: "Card surcharge"}
    end
  end

  # The Finance payment the shop recorded for the order (its revenue lineage).
  defp shop_payment_id(context, order) do
    case Finance.revenue_lineage(context, Shop.order_source_type(), order.id) do
      %{payments: [payment | _]} -> Map.get(payment, :id)
      _none -> nil
    end
  end

  defp record(context, user_id, intent, purpose) do
    params =
      %{
        "amount_cents" => intent.amount_cents,
        "currency" => intent.currency,
        "paid_on" => paid_on(context, intent),
        "idempotency_key" => "payment-intent:" <> intent.id
      }
      |> Map.merge(terminal_params(intent))
      |> Map.merge(surcharge_params(context, intent))
      |> Map.merge(Map.reject(purpose, fn {_key, value} -> is_nil(value) end))

    with {:ok, received} <- ReceiveFinancePayment.record_terminal(context, user_id, params) do
      {:ok, FinanceFulfilment.fulfilled(received)}
    end
  end

  defp terminal_params(intent) do
    %{
      "payment_intent_id" => intent.id,
      "provider" => intent.provider,
      "provider_transaction_id" => intent.provider_transaction_id,
      "created_by_id" => intent.created_by_id,
      # ADR-264: kept on the payment; the surcharge is recorded apart.
      "tip_cents" => intent.tip_cents || 0,
      "surcharge_cents" => intent.surcharge_cents || 0
    }
  end

  defp paid_on(context, intent), do: context |> paid_on_date(intent) |> Date.to_iso8601()

  defp paid_on_date(context, intent),
    do:
      Organizations.local_today(
        context.organization_id,
        intent.succeeded_at || DateTime.utc_now()
      )

  @doc "Money given back for a terminal payment: a Finance reversal (the shop records its own)."
  def reverse(_context, %{finance_payment_id: nil}, _refund), do: {:ok, %{}}
  def reverse(_context, %{purpose_type: "shop_order"}, _refund), do: {:ok, %{}}

  # ADR-264: a walk-in's sale is a stream payment with no membership.
  def reverse(context, %{purpose_type: "free_sale", user_id: nil} = intent, refund) do
    with {:ok, reversal} <-
           Finance.reverse_stream_payment(context, %{
             membership_payment_id: intent.finance_payment_id,
             amount_cents: refund.amount_cents,
             user_id: nil,
             reason: refund.reason || "terminal refund",
             created_by_id: refund.created_by_id,
             idempotency_key: "payment-refund:" <> refund.id,
             params: %{"payment_intent_id" => intent.id, "payment_refund_id" => refund.id}
           }) do
      credited(context, intent, reversal, refund)
    end
  end

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
      credited(context, intent, reversal, refund)
    end
  end

  # ADR-262: the refund credits the payment's fiscal document.
  defp credited(context, intent, reversal, refund) do
    with {:ok, note} <-
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
