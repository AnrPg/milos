defmodule Palee.Shop.Observability do
  @moduledoc """
  The shop's `:telemetry` contract (ADR-192 §5). The shop's use cases call
  these after their transaction commits; `PaleeWeb.Telemetry` turns them
  into Prometheus metrics and the one-minute log summary.

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:palee, :shop, :order, :placed]` | `count`, `amount_cents` | `channel` |
  | `[:palee, :shop, :order, :paid]` | `count`, `amount_cents` | `channel`, `method` |
  | `[:palee, :shop, :order, :refunded]` | `count`, `amount_cents` | `channel` |
  | `[:palee, :shop, :stock, :movement]` | `count`, `quantity` | `kind` |
  | `[:palee, :shop, :stock, :low]` | `count` | `status` |
  | `[:palee, :shop, :reconciliation, :checked]` | `days`, `drifted_days`, `drift_cents` | `result` |

  Every metadata value is folded onto a closed list, so a label can never
  carry an id or free text.
  """

  @channels ~w(online pos)
  @methods ~w(cash card_manual bank_transfer online other)
  @kinds ~w(receive sale refund_restock adjustment transfer reserve release)
  @statuses ~w(ok low critical out)

  def order_placed(channel, amount_cents),
    do:
      emit([:order, :placed], %{amount_cents: amount_cents}, %{channel: fold(channel, @channels)})

  def order_paid(channel, method, amount_cents) do
    emit([:order, :paid], %{amount_cents: amount_cents}, %{
      channel: fold(channel, @channels),
      method: fold(method, @methods)
    })
  end

  def order_refunded(channel, amount_cents),
    do:
      emit([:order, :refunded], %{amount_cents: amount_cents}, %{
        channel: fold(channel, @channels)
      })

  def stock_moved(kind, quantity),
    do: emit([:stock, :movement], %{quantity: quantity}, %{kind: fold(kind, @kinds)})

  @doc "A variant crossed into a low-stock status (`low`, `critical`, `out`)."
  def low_stock(status), do: emit([:stock, :low], %{}, %{status: fold(status, @statuses)})

  def reconciliation_checked(%{days: days, drifted: drifted, drift_cents: drift}) do
    :telemetry.execute(
      [:palee, :shop, :reconciliation, :checked],
      %{days: length(days), drifted_days: length(drifted), drift_cents: drift},
      %{result: if(drifted == [], do: "ok", else: "drift")}
    )
  end

  defp emit(event, measurements, metadata) do
    :telemetry.execute([:palee, :shop | event], Map.put(measurements, :count, 1), metadata)
  end

  defp fold(value, allowed) when is_atom(value) and not is_nil(value),
    do: fold(Atom.to_string(value), allowed)

  defp fold(value, allowed), do: if(value in allowed, do: value, else: "other")
end
