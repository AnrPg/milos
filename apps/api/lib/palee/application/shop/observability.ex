defmodule Palee.Application.Shop.Observability do
  @moduledoc """
  The shop's observability (ADR-190), in one place so every use case emits
  the same three signals:

    * `:telemetry` events, `[:palee, :shop, :order, :placed | :paid | :ready
      | :picked_up | :cancelled | :refunded]`, `[:palee, :shop, :stock,
      :moved]`, `[:palee, :shop, :stock, :status_changed]` and `[:palee,
      :shop, :variant, :price_changed]`, measurements in cents and units,
      metadata with `organization_id`, ids, channel and `revenue_stream:
      "shop"`;
    * the audit trail: an `analytics_events` row per fact (ADR-123
      instrumentation, `context_type` `shop_order` / `shop_stock_movement` /
      `shop_product` / `shop_variant`), with the acting user;
    * a structured log line with `organization_id` and `order_id` in its
      metadata.

  All three are best effort: they never change the outcome of the sale.
  """

  require Logger

  alias Palee.Application.TrackAnalyticsEvent

  @order_events [:placed, :paid, :ready, :picked_up, :cancelled, :refunded]

  @doc "An order fact; `extra` adds measurements (`amount_cents`) and metadata."
  def order(event, context, order, extra \\ %{}) when event in @order_events do
    metadata = %{
      organization_id: context.organization_id,
      actor_id: Map.get(context, :user_id),
      order_id: order.id,
      order_number: order.number,
      channel: order.channel,
      payment_mode: order.payment_mode,
      source: order.source,
      pickup_location_id: order.pickup_location_id,
      finance_invoice_id: order.finance_invoice_id,
      revenue_stream: "shop"
    }

    measurements = %{
      count: 1,
      total_cents: order.total_cents,
      amount_cents: Map.get(extra, :amount_cents, order.total_cents),
      units: order |> Map.get(:lines, []) |> lines_units()
    }

    safely(fn -> :telemetry.execute([:palee, :shop, :order, event], measurements, metadata) end)

    Logger.info("shop_order_#{event} order=#{order.id} number=#{order.number}",
      organization_id: context.organization_id,
      order_id: order.id,
      shop_event: event,
      channel: order.channel,
      amount_cents: measurements.amount_cents
    )

    TrackAnalyticsEvent.call("shop_order_#{event}", context, order, %{
      metadata:
        Map.merge(
          %{
            finance_invoice_id: order.finance_invoice_id,
            pickup_location_id: order.pickup_location_id,
            promotion_code: order.promotion_code,
            source_ref_id: order.source_ref_id,
            amount_cents: measurements.amount_cents
          },
          Map.get(extra, :metadata, %{})
        )
    })

    :ok
  end

  @doc "Ledger rows written by one change."
  def stock_moved(context, movements) do
    Enum.each(movements, fn movement ->
      metadata = %{
        organization_id: context.organization_id,
        actor_id: Map.get(context, :user_id),
        variant_id: movement.variant_id,
        location_id: movement.location_id,
        kind: movement.kind,
        reason: movement.reason,
        order_id: movement.order_id
      }

      safely(fn ->
        :telemetry.execute(
          [:palee, :shop, :stock, :moved],
          %{count: 1, quantity: movement.quantity},
          metadata
        )
      end)

      Logger.info(
        "shop_stock_moved variant=#{movement.variant_id} kind=#{movement.kind} q=#{movement.quantity}",
        organization_id: context.organization_id,
        order_id: movement.order_id,
        variant_id: movement.variant_id
      )

      TrackAnalyticsEvent.call("shop_stock_moved", context, movement, %{
        metadata: %{order_id: movement.order_id, transfer_id: movement.transfer_id}
      })
    end)
  end

  @doc "A variant's stock status changed (`refresh_stock_status` rows)."
  def stock_status_changed(context, %{
        variant: variant,
        previous: previous,
        assessment: assessment
      }) do
    safely(fn ->
      :telemetry.execute(
        [:palee, :shop, :stock, :status_changed],
        %{count: 1, available: variant.stock.available},
        %{
          organization_id: context.organization_id,
          variant_id: variant.id,
          product_id: variant.product_id,
          previous: previous,
          status: assessment.status
        }
      )
    end)

    TrackAnalyticsEvent.call(
      "shop_stock_status_changed",
      context,
      Map.put(variant, :stock_status, assessment.status),
      %{metadata: %{previous: previous, days_left: assessment.days_left}}
    )
  end

  @doc "A catalog fact (`shop_product_created`, `shop_product_status_changed`, `shop_product_promoted`)."
  def catalog(event_name, context, product, metadata \\ %{}) do
    Logger.info("#{event_name} product=#{product.id}",
      organization_id: context.organization_id,
      product_id: product.id
    )

    TrackAnalyticsEvent.call(event_name, context, product, %{metadata: metadata})
  end

  @doc """
  A variant's price, compare-at or cost changed: the one event the price
  history is built from (the analytics helper's ledger reads it).
  """
  def price_changed(context, before, variant) do
    metadata = %{
      organization_id: context.organization_id,
      actor_id: Map.get(context, :user_id),
      variant_id: variant.id,
      product_id: variant.product_id,
      currency: variant.currency
    }

    safely(fn ->
      :telemetry.execute(
        [:palee, :shop, :variant, :price_changed],
        %{
          price_cents: variant.price_cents,
          previous_price_cents: before && before.price_cents
        },
        metadata
      )
    end)

    TrackAnalyticsEvent.call("shop_variant_price_changed", context, variant, %{
      metadata: %{
        previous_price_cents: before && before.price_cents,
        previous_compare_at_price_cents: before && before.compare_at_price_cents,
        previous_cost_price_cents: before && before.cost_price_cents
      }
    })
  end

  defp lines_units(lines) when is_list(lines), do: Enum.sum(Enum.map(lines, & &1.quantity))
  defp lines_units(_lines), do: 0

  defp safely(fun) do
    fun.()
  rescue
    error -> Logger.warning("shop_telemetry_failed #{Exception.message(error)}")
  end
end
