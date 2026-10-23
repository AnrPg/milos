defmodule Palee.Application.Shop.OrderMoney do
  @moduledoc """
  The Finance side of a shop order (ADR-190), shared by checkout, desk sales
  and fulfilment. Every call runs inside the caller's `Shop.transaction/2`,
  so the order, its stock movements and its Finance rows commit together or
  not at all.

    * `invoice/3`: the order's issued invoice, one `shop_item` line per order
      line (`source_type: shop_order_line`), linked back on the order and its
      lines.
    * `settle/4`: the payment (`source_type: shop_order`, idempotent per
      order), and the order's `pay` transition.
    * `refund/4`: the reversal of that payment (it inherits stream and
      source), with the member's refund receipt (ADR-126).
  """

  alias Palee.{Finance, Organizations, Shop}

  @doc "Creates the order's invoice and links it."
  def invoice(context, order, today) do
    with {:ok, invoice} <-
           Finance.record_stream_invoice(context, Shop.finance_invoice(order, order.lines, today)),
         :ok <- link_lines(context, order.lines, invoice.lines),
         {:ok, order} <- Shop.update_order(context, order.id, %{finance_invoice_id: invoice.id}) do
      {:ok, order, invoice}
    end
  end

  defp link_lines(context, order_lines, invoice_lines) do
    by_source = Map.new(invoice_lines, &{&1.source_id, &1.id})

    Enum.reduce_while(order_lines, :ok, fn line, :ok ->
      case Shop.update_order_line(context, line.id, %{finance_invoice_line_id: by_source[line.id]}) do
        {:ok, _line} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Records the payment of the whole order with `method` and moves it to
  `paid`. `extra` lands in the payment's params (provider, reference).
  """
  def settle(context, order, method, extra \\ %{}) do
    today = Organizations.local_today(context.organization_id)
    now = DateTime.utc_now()

    with {:ok, attrs} <-
           Shop.order_transition(order, :pay, %{at: now, amount_cents: order.total_cents}),
         {:ok, payment} <-
           Finance.record_stream_payment(
             context,
             Shop.finance_payment(order, method, today, extra)
           ),
         {:ok, order} <-
           Shop.update_order(
             context,
             order.id,
             Map.merge(attrs, %{
               payment_provider: extra[:provider],
               payment_reference: extra[:reference],
               payment_idempotency_key: extra[:idempotency_key]
             })
           ) do
      {:ok, order, payment}
    end
  end

  @doc """
  Refunds `amount_cents` of the order's payment and moves the order to
  `partially_refunded` / `refunded`.
  """
  def refund(context, order, amount_cents, attrs) do
    lineage = Finance.revenue_lineage(context, Shop.order_source_type(), order.id)

    case Enum.find(lineage.reversals, &(&1.idempotency_key == attrs[:idempotency_key])) do
      nil -> new_refund(context, order, amount_cents, attrs, lineage)
      # A retried refund: the first one stands, nothing moves twice.
      existing -> {:ok, order, Map.put(existing, :replayed, true)}
    end
  end

  defp new_refund(context, order, amount_cents, attrs, lineage) do
    with [payment | _] <- lineage.payments || {:error, :payment_not_found},
         {:ok, order_attrs} <-
           Shop.order_transition(order, :refund, %{amount_cents: amount_cents}),
         {:ok, reversal} <-
           Finance.reverse_stream_payment(context, %{
             membership_payment_id: payment.id,
             amount_cents: amount_cents,
             user_id: order.user_id,
             reason: attrs[:reason],
             created_by_id: context.user_id,
             idempotency_key: attrs[:idempotency_key],
             receipt_party: attrs[:receipt_party],
             params: %{
               "shop_order_id" => order.id,
               "shop_order_number" => order.number,
               "order_line_ids" => attrs[:order_line_ids] || []
             }
           }),
         {:ok, order} <- Shop.update_order(context, order.id, order_attrs) do
      {:ok, order, reversal}
    else
      [] -> {:error, :payment_not_found}
      error -> error
    end
  end

  @doc "Voids the invoice of an unpaid order (cancellation)."
  def void(_context, %{finance_invoice_id: nil}, _reason), do: :ok

  def void(context, order, reason) do
    case Finance.void_stream_invoice(context, order.finance_invoice_id, %{reason: reason}) do
      {:ok, _invoice} -> :ok
      error -> error
    end
  end
end
