defmodule Palee.Shop.Domain.RevenueLineage do
  @moduledoc """
  The Finance rows a shop order produces (ADR-190), pure. Every one carries
  `revenue_stream: "shop"` and a source, so shop money is traceable from a
  Finance total down to the line, order, variant and product:

      finance_invoice_line (line_type shop_item, source_type shop_order_line, source_id)
        -> shop_order_line -> shop_variant -> shop_product
      membership_payment (source_type shop_order, source_id)        -> shop_order
      finance_payment_reversal (inherits the payment's stream/source) -> shop_order

  `params` on each row repeat the order number, product, variant and SKU so
  exports stay self-describing after the catalog changes.
  """

  @stream "shop"
  @order_source "shop_order"
  @line_source "shop_order_line"

  def stream, do: @stream
  def order_source, do: @order_source
  def line_source, do: @line_source

  @doc "The invoice (with its lines) for an order and its persisted lines."
  @spec invoice(map(), [map()], Date.t()) :: map()
  def invoice(order, lines, today) do
    %{
      "revenue_stream" => @stream,
      "membership_id" => order.membership_id,
      "user_id" => order.user_id,
      "invoice_type" => "manual",
      "issue_date" => today,
      "due_date" => today,
      "currency" => order.currency,
      "notes" => "Shop order ##{order.number}",
      "params" => order_params(order),
      "lines" => Enum.map(lines, &invoice_line(order, &1))
    }
  end

  @doc "One invoice line for one order line."
  @spec invoice_line(map(), map()) :: map()
  def invoice_line(order, line) do
    %{
      "line_type" => "shop_item",
      "charge_category" => "product",
      "revenue_stream" => @stream,
      "source_type" => @line_source,
      "source_id" => line.id,
      "description" => description(line),
      "quantity" => line.quantity,
      "unit_amount_cents" => line.unit_price_cents,
      "discount_cents" => line.discount_cents,
      "total_cents" => line.total_cents,
      "params" =>
        Map.merge(order_params(order), %{
          "order_line_id" => line.id,
          "product_id" => line.product_id,
          "variant_id" => line.variant_id,
          "sku" => line.sku,
          "tax_class" => line.tax_class,
          "cost_price_cents" => line.cost_price_cents
        })
    }
  end

  @doc "The payment that settles an order."
  @spec payment(map(), atom() | String.t(), Date.t(), map()) :: map()
  def payment(order, method, today, extra \\ %{}) do
    %{
      "revenue_stream" => @stream,
      "source_type" => @order_source,
      "source_id" => order.id,
      "membership_id" => order.membership_id,
      "finance_invoice_id" => order.finance_invoice_id,
      "amount_cents" => order.total_cents,
      "currency" => order.currency,
      "paid_on" => today,
      "payment_method" => finance_method(method),
      "payment_status" => "paid",
      "notes" => "Shop order ##{order.number}",
      "params" => Map.merge(order_params(order), stringify(extra))
    }
  end

  @doc """
  Finance's payment method for a shop payment mode. Online payments are
  recorded as `other` with the provider in `params` until Finance has a
  provider method.
  """
  @spec finance_method(atom() | String.t()) :: String.t()
  def finance_method(method) when method in [:cash, "cash"], do: "cash"
  def finance_method(method) when method in [:card_manual, "card_manual"], do: "card_manual"
  def finance_method(method) when method in [:bank_transfer, "bank_transfer"], do: "bank_transfer"
  def finance_method(_method), do: "other"

  @doc """
  How a refund of `amount_cents` is spread over the order lines it names
  (`[%{order_line_id, quantity}]`), capped by what each line can still give
  back. Without named lines the amount is taken as given.
  """
  @spec allocate_refund([map()], [map()]) :: {:ok, [map()], non_neg_integer()} | {:error, atom()}
  def allocate_refund(order_lines, requested) when is_list(requested) and requested != [] do
    by_id = Map.new(order_lines, &{&1.id, &1})

    Enum.reduce_while(requested, {:ok, [], 0}, fn item, {:ok, acc, total} ->
      id = Map.get(item, :order_line_id, Map.get(item, "order_line_id"))
      quantity = Map.get(item, :quantity, Map.get(item, "quantity"))
      restock = Map.get(item, :restock, Map.get(item, "restock", false)) in [true, "true"]

      with %{} = line <- Map.get(by_id, id) || {:error, :order_line_not_found},
           true <- (is_integer(quantity) and quantity > 0) || {:error, :invalid_quantity},
           true <-
             quantity <= line.quantity - line.refunded_quantity ||
               {:error, :refund_exceeds_quantity} do
        cents = line_refund_cents(line, quantity)

        {:cont,
         {:ok, [%{line: line, quantity: quantity, cents: cents, restock: restock} | acc],
          total + cents}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, allocations, total} -> {:ok, Enum.reverse(allocations), total}
      error -> error
    end
  end

  def allocate_refund(_order_lines, _requested), do: {:error, :refund_lines_required}

  @doc """
  The money a partial line refund gives back: the line's net total spread
  evenly over its units, the last unit taking the rounding remainder.
  """
  @spec line_refund_cents(map(), pos_integer()) :: non_neg_integer()
  def line_refund_cents(line, quantity) do
    remaining_units = line.quantity - line.refunded_quantity
    remaining_cents = line.total_cents - line.refunded_cents

    if quantity >= remaining_units,
      do: remaining_cents,
      else: div(line.total_cents * quantity, line.quantity)
  end

  defp description(%{product_title: title, variant_title: nil}), do: title
  defp description(%{product_title: title, variant_title: variant}), do: "#{title} (#{variant})"

  defp order_params(order) do
    %{
      "shop_order_id" => order.id,
      "shop_order_number" => order.number,
      "channel" => to_string(order.channel),
      "source" => to_string(order.source),
      "pickup_location_id" => order.pickup_location_id
    }
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
