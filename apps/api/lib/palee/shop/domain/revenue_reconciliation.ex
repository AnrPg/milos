defmodule Palee.Shop.Domain.RevenueReconciliation do
  @moduledoc """
  The shop's daily revenue reconciliation (ADR-192 §5). For each gym-local
  day three independent figures must agree:

    * `orders_cents`: the net total of the shop orders paid that day
      (order totals minus their refunds);
    * `invoice_lines_cents`: the net of the `shop`-stream invoice lines of
      that day (lines minus refund lines or reversals);
    * `payments_cents`: the shop payments of that day minus their refunds.

  A day drifts when any two differ. Pure: the caller reads the figures.
  """

  @type day_figures :: %{
          day: Date.t(),
          orders_cents: integer(),
          invoice_lines_cents: integer(),
          payments_cents: integer()
        }

  @doc """
  Compares per-day figures, given as three maps of `day => cents`. Every day
  that appears in any of them is checked.
  """
  @spec compare(%{Date.t() => integer()}, %{Date.t() => integer()}, %{Date.t() => integer()}) ::
          %{days: [map()], drifted: [map()], ok?: boolean(), drift_cents: non_neg_integer()}
  def compare(orders, lines, payments) do
    days =
      [orders, lines, payments]
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()
      |> Enum.sort(Date)
      |> Enum.map(fn day ->
        check(%{
          day: day,
          orders_cents: Map.get(orders, day, 0),
          invoice_lines_cents: Map.get(lines, day, 0),
          payments_cents: Map.get(payments, day, 0)
        })
      end)

    drifted = Enum.reject(days, & &1.ok?)

    %{
      days: days,
      drifted: drifted,
      ok?: drifted == [],
      drift_cents: Enum.reduce(drifted, 0, &(&2 + &1.drift_cents))
    }
  end

  @doc "One day's verdict: the largest gap between the three figures."
  @spec check(day_figures()) :: map()
  def check(%{orders_cents: orders, invoice_lines_cents: lines, payments_cents: payments} = day) do
    values = [orders, lines, payments]
    drift = Enum.max(values) - Enum.min(values)

    Map.merge(day, %{
      ok?: drift == 0,
      drift_cents: drift,
      orders_vs_lines_cents: orders - lines,
      lines_vs_payments_cents: lines - payments
    })
  end
end
