defmodule Palee.Infrastructure.Observability.RevenueStreamBridge do
  @moduledoc """
  ADR-192: shop money joins the revenue-by-stream counters.

  Finance's own payment commands emit `[:palee, :finance, :revenue, ...]`
  (`Palee.Finance.RevenueTelemetry`). Shop payments and refunds go through
  ADR-190's stream store, whose idempotent replays make the store a poor
  place to count, so the shop's order events (`:paid`, `:refunded`, emitted
  once per real transition by `Palee.Application.Shop.Observability`) are
  re-emitted as `shop`-stream revenue events here.
  """

  alias Palee.Finance.RevenueTelemetry

  @handler_id {__MODULE__, :shop_orders}

  def attach do
    :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      [[:palee, :shop, :order, :paid], [:palee, :shop, :order, :refunded]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:palee, :shop, :order, event], measurements, metadata, _config) do
    amount = Map.get(measurements, :amount_cents)
    currency = Map.get(metadata, :currency, "EUR")

    case event do
      :paid -> RevenueTelemetry.payment_recorded("shop", amount, currency)
      :refunded -> RevenueTelemetry.refund_recorded("shop", amount, currency)
    end
  rescue
    # A raising handler is detached for good; never let one sample do that.
    _error -> :ok
  end
end
