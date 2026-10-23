defmodule PaleeWeb.ShopJSON do
  @moduledoc "Renders shop records (ADR-190) as plain JSON maps."

  alias Palee.Shop

  @order_fields [
    :id,
    :number,
    :status,
    :payment_status,
    :channel,
    :payment_mode,
    :user_id,
    :customer_name,
    :pickup_location_id,
    :currency,
    :subtotal_cents,
    :discount_cents,
    :total_cents,
    :paid_cents,
    :refunded_cents,
    :source,
    :source_ref_id,
    :promotion_code,
    :finance_invoice_id,
    :fiscal_receipt_ref,
    :note,
    :placed_at,
    :expires_at,
    :paid_at,
    :ready_at,
    :picked_up_at,
    :cancelled_at,
    :cancel_reason
  ]

  @line_fields [
    :id,
    :product_id,
    :variant_id,
    :product_title,
    :variant_title,
    :sku,
    :quantity,
    :unit_price_cents,
    :discount_cents,
    :total_cents,
    :refunded_quantity,
    :refunded_cents,
    :location_id,
    :finance_invoice_line_id
  ]

  @staff_line_fields @line_fields ++ [:cost_price_cents, :tax_class]

  @movement_fields [
    :id,
    :variant_id,
    :location_id,
    :kind,
    :quantity,
    :reason,
    :note,
    :unit_cost_cents,
    :order_id,
    :order_line_id,
    :transfer_id,
    :user_id,
    :occurred_at
  ]

  @doc "An order as staff see it (with cost and tax snapshots on its lines)."
  def staff_order(order), do: order(order, @staff_line_fields)

  @doc "An order as its buyer sees it."
  def member_order(order), do: order(order, @line_fields)

  defp order(order, line_fields) do
    order
    |> Map.take(@order_fields)
    |> Map.merge(%{
      state: Shop.order_state(order),
      revenue_stream: Shop.revenue_stream(),
      lines: Enum.map(lines(order), &Map.take(&1, line_fields))
    })
  end

  defp lines(%{lines: lines}) when is_list(lines), do: lines
  defp lines(_order), do: []

  def product(product) do
    product
    |> Map.drop([:__meta__, :organization_id, :created_by_id])
    |> Map.update(:variants, [], &Enum.map(&1, fn variant -> variant(variant) end))
  end

  def variant(variant), do: Map.drop(variant, [:__meta__, :organization_id])

  def movement(movement), do: Map.take(movement, @movement_fields)

  @promotion_code_fields [
    :id,
    :product_id,
    :code,
    :discount_percent,
    :discount_cents,
    :max_redemptions,
    :redemptions,
    :starts_at,
    :ends_at,
    :active,
    :post_id,
    :inserted_at
  ]

  def promotion_code(code) do
    code
    |> Map.take(@promotion_code_fields)
    |> Map.put(:status, Map.get(code, :status) || Shop.promotion_status(code, DateTime.utc_now()))
  end
end
