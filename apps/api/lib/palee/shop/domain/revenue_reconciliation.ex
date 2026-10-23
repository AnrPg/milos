defmodule Palee.Shop.Domain.RevenueReconciliation do
  @moduledoc """
  The shop's daily revenue reconciliation (ADR-192 §5). For each gym-local
  business day and currency three independently stored figures must agree,
  to the cent:

    * `orders_cents` - the shop orders paid that day: order totals minus the
      refunds recorded on the orders;
    * `invoice_lines_cents` - Finance's `shop`-stream invoice lines of those
      orders minus the refunds (reversals) of their payments;
    * `payments_cents` - Finance's `shop`-stream payments of that business
      day minus their refunds.

  Refunds belong to the day of the sale they refund, in all three figures,
  the way Finance attributes reversals to the original payment.

  Figures arrive as maps keyed by `{day, currency}`. Integer cents only: a
  day reconciles when the three integers are equal. Pure.
  """

  @type key :: {Date.t(), String.t()}
  @type figures :: %{key() => integer()}

  @doc "Compares the three figures for every day and currency any of them names."
  @spec compare(figures(), figures(), figures()) :: %{
          days: [map()],
          drifted: [map()],
          ok: boolean(),
          drift_cents: non_neg_integer()
        }
  def compare(orders, lines, payments) do
    days =
      [orders, lines, payments]
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()
      |> Enum.sort_by(fn {day, currency} -> {Date.to_gregorian_days(day), currency} end)
      |> Enum.map(fn {day, currency} = key ->
        check(%{
          day: day,
          currency: currency,
          orders_cents: Map.get(orders, key, 0),
          invoice_lines_cents: Map.get(lines, key, 0),
          payments_cents: Map.get(payments, key, 0)
        })
      end)

    drifted = Enum.reject(days, & &1.ok)

    %{
      days: days,
      drifted: drifted,
      ok: drifted == [],
      drift_cents: Enum.reduce(drifted, 0, &(&2 + &1.drift_cents))
    }
  end

  @doc "One day's verdict: the largest gap between the three figures."
  @spec check(map()) :: map()
  def check(%{orders_cents: orders, invoice_lines_cents: lines, payments_cents: payments} = day)
      when is_integer(orders) and is_integer(lines) and is_integer(payments) do
    drift = Enum.max([orders, lines, payments]) - Enum.min([orders, lines, payments])

    Map.merge(day, %{
      ok: drift == 0,
      drift_cents: drift,
      orders_vs_lines_cents: orders - lines,
      lines_vs_payments_cents: lines - payments
    })
  end
end
