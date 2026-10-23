defmodule Palee.Application.Shop.MemberShop do
  @moduledoc """
  What a member (or a visitor) reads of a box's shop (ADR-190):

    * `catalog/2` and `product/2`: the published products sold in the app,
      `members_only` ones only to members of the box; prices, options and
      availability per variant (never cost prices or stock counts beyond
      "available" and "low");
    * `public_catalog/2`: the products for `anyone` of an active business,
      for the public box page;
    * `my_orders/1`, `my_order/2`: the member's own orders;
    * `billing_transactions/2`: the member's shop money for
      `Εγώ › Πληρωμές › Συναλλαγές` (the facade the member-billing endpoint
      `GET /api/me/billing/transactions` calls), one entry per order with
      its Finance invoice, payments and refunds, all `revenue_stream: "shop"`.
  """

  alias Palee.Application.GoLive
  alias Palee.Application.Shop.Checkout
  alias Palee.{Facility, Finance, Organizations, Shop}

  @public_variant_fields [
    :id,
    :product_id,
    :title,
    :option_values,
    :sku,
    :price_cents,
    :currency,
    :compare_at_price_cents,
    :position,
    :archived_at
  ]

  @doc """
  The member's storefront of the box: whether the shop is open (it has
  products on sale and the business may take this member's money: a demo
  business is closed to real people, ADR-184), its products, categories and
  pickup branches, the member discount that applies to them, and whether
  online payment is offered.
  """
  def storefront(context) do
    products = catalog(context)
    terms = Finance.member_shop_terms(context, context.user_id)

    closed_reason =
      cond do
        products == [] -> :no_products
        GoLive.check_payment(context, context.user_id) != :ok -> :business_not_activated
        true -> nil
      end

    %{
      open: is_nil(closed_reason),
      closed_reason: closed_reason,
      products: products,
      categories:
        products |> Enum.map(& &1.category) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq(),
      pickup_locations:
        context
        |> Facility.list_locations()
        |> Enum.map(&%{id: &1.id, name: &1.name, address: Map.get(&1, :address)}),
      member_discount: Checkout.member_discount(terms),
      online_payment: Checkout.online_payment(context)
    }
  end

  @doc """
  «Ειδοποίησέ με»: the member asks to hear when a variant of a product they
  can buy is back in stock (asking again re-arms a sent alert).
  """
  def subscribe_back_in_stock(context, variant_id) do
    with {:ok, variant} <- buyable_variant(context, variant_id),
         {:ok, alert} <- Shop.subscribe_stock_alert(context, variant.id, context.user_id) do
      {:ok, alert_view(alert, variant)}
    end
  end

  def unsubscribe_back_in_stock(context, variant_id) do
    with {:ok, variant} <- buyable_variant(context, variant_id),
         do: Shop.unsubscribe_stock_alert(context, variant.id, context.user_id)
  end

  @doc "The member's stock alerts, newest first."
  def back_in_stock_alerts(context) do
    alerts = Shop.list_stock_alerts(context, %{user_id: context.user_id})

    variants =
      case alerts do
        [] ->
          %{}

        _some ->
          context
          |> Shop.list_variants(%{ids: Enum.map(alerts, & &1.variant_id)})
          |> Map.new(&{&1.id, &1})
      end

    Enum.map(alerts, &alert_view(&1, variants[&1.variant_id]))
  end

  defp alert_view(alert, variant) do
    %{
      id: alert.id,
      variant_id: alert.variant_id,
      product_id: variant && variant.product_id,
      notified_at: alert.notified_at,
      inserted_at: alert.inserted_at,
      available: variant && availability(variant) != "sold_out"
    }
  end

  defp buyable_variant(context, variant_id) do
    with %{archived_at: nil} = variant <-
           Shop.get_variant(context, variant_id) || {:error, :not_found},
         {:ok, _product} <- product(context, variant.product_id) do
      {:ok, variant}
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end

  @doc "The member's catalog of the box in `context`."
  def catalog(context, filters \\ %{}) do
    context
    |> Shop.list_products(Map.merge(filters, %{statuses: [:published], sell_in_app: true}))
    |> Enum.filter(&Shop.visible_to?(&1, :member))
    |> Enum.map(&public_product/1)
  end

  @doc "One product of the member's catalog."
  def product(context, id) do
    case Shop.get_product(context, id) do
      %{} = product ->
        if Shop.visible_to?(product, :member),
          do: {:ok, public_product(product)},
          else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "The products of an active business sold to anyone (public box page)."
  def public_catalog(organization_id, filters \\ %{}) do
    organization = Organizations.get_by_id(organization_id)

    if organization && not Organizations.business_gated?(organization) do
      %{organization_id: organization_id}
      |> Shop.list_products(
        Map.merge(filters, %{statuses: [:published], sell_in_app: true, visibility: :anyone})
      )
      |> Enum.filter(&Shop.visible_to?(&1, :visitor))
      |> Enum.map(&public_product/1)
    else
      []
    end
  end

  @doc "The member's own orders, newest first."
  def my_orders(context), do: Shop.list_orders(context, %{user_id: context.user_id, limit: 200})

  def my_order(context, id) do
    case Shop.get_order(context, id) do
      %{user_id: user_id} = order when user_id == context.user_id -> {:ok, order}
      _other -> {:error, :not_found}
    end
  end

  @doc """
  The member's shop transactions (newest first), for the member-billing
  history. Each entry:

      %{kind: "shop_order", revenue_stream: "shop", order_id, order_number,
        state, channel, placed_at, currency, total_cents, paid_cents,
        refunded_cents, finance_invoice_id, invoice_number, invoice_status,
        fiscal_receipt_ref, lines: [%{order_line_id, product_id, variant_id,
        title, quantity, total_cents, refunded_quantity}], payments:
        [%{id, amount_cents, payment_method, paid_on}], refunds: [%{id,
        amount_cents, occurred_on, reason}]}

  Desk sales to the member are included.
  """
  def billing_transactions(context, user_id) do
    invoices =
      context
      |> Finance.stream_invoices_for_user(Shop.revenue_stream(), user_id)
      |> Map.new(&{&1.id, &1})

    context
    |> Shop.list_orders(%{user_id: user_id, limit: 500})
    |> Enum.map(&transaction(&1, Map.get(invoices, &1.finance_invoice_id)))
  end

  defp transaction(order, invoice) do
    %{
      kind: "shop_order",
      revenue_stream: Shop.revenue_stream(),
      order_id: order.id,
      order_number: order.number,
      state: Shop.order_state(order),
      channel: order.channel,
      placed_at: order.placed_at,
      currency: order.currency,
      total_cents: order.total_cents,
      paid_cents: order.paid_cents,
      refunded_cents: order.refunded_cents,
      finance_invoice_id: order.finance_invoice_id,
      invoice_number: invoice && invoice.invoice_number,
      invoice_status: invoice && invoice.status,
      fiscal_receipt_ref: (invoice && invoice.fiscal_receipt_ref) || order.fiscal_receipt_ref,
      lines:
        Enum.map(order.lines, fn line ->
          %{
            order_line_id: line.id,
            product_id: line.product_id,
            variant_id: line.variant_id,
            title: line_title(line),
            quantity: line.quantity,
            total_cents: line.total_cents,
            refunded_quantity: line.refunded_quantity
          }
        end),
      payments:
        Enum.map((invoice && invoice.payments) || [], fn payment ->
          Map.take(payment, [:id, :amount_cents, :currency, :payment_method, :paid_on])
        end),
      refunds:
        Enum.map((invoice && invoice.reversals) || [], fn reversal ->
          Map.take(reversal, [:id, :amount_cents, :currency, :occurred_on, :reason])
        end)
    }
  end

  defp line_title(%{product_title: title, variant_title: nil}), do: title
  defp line_title(%{product_title: title, variant_title: variant}), do: "#{title} (#{variant})"

  @doc "A product as members see it: no cost prices, no stock counts by branch."
  def public_product(product) do
    variants =
      product.variants
      |> Enum.filter(&is_nil(&1.archived_at))
      |> Enum.map(fn variant ->
        variant
        |> Map.take(@public_variant_fields)
        |> Map.put(:available, availability(variant))
      end)

    product
    |> Map.take([
      :id,
      :title,
      :description,
      :category,
      :media_ids,
      :options,
      :visibility,
      :per_person_limit,
      :all_locations,
      :location_ids,
      :published_at
    ])
    |> Map.put(:variants, variants)
  end

  defp availability(%{track_inventory: false}), do: "in_stock"
  defp availability(%{stock: %{available: available}}) when available <= 0, do: "sold_out"
  defp availability(%{stock_status: status}) when status in [:low, :critical], do: "low"
  defp availability(_variant), do: "in_stock"
end
