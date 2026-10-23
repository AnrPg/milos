defmodule Palee.Shop.Domain.SalesReport do
  @moduledoc """
  The maths of the shop reports (ADR-192 §4). Pure: no clock, no database.

  The report store aggregates in the database and hands over **groups**, so
  the work here is proportional to the number of days, products or
  channels, never to the number of orders:

    * an **order group** is `%{orders, gross_cents, refunded_cents}` plus the
      dimension it is grouped by (`:day`, `:channel`, `:location_id`,
      `:promotion_code`, `:campaign_id`, `:source` + `:source_ref_id`);
    * a **line group** is `%{product_id, product_name, variant_id,
      variant_name, units, refunded_units, revenue_cents, refunded_cents,
      costed_revenue_cents, cost_cents}`, where the last two cover only the
      lines whose cost price was known when sold;
    * a **stock row** is `%{variant_id, product_id, product_name,
      variant_name, location_id, on_hand, reserved, unit_cost_cents,
      low_stock_threshold, sold_units}`.

  Money is integer cents throughout; only percentages are floats. Refunds
  belong to the sale they refund (the order's paid day, its product, its
  channel), so net = gross - refunds everywhere.
  """

  @type cents :: integer()

  @doc "Per-day series over `[from, to]` (every day present) and the totals."
  def sales(day_groups, %Date{} = from, %Date{} = to) do
    by_day = Enum.group_by(day_groups, & &1.day)

    series =
      Date.range(from, to)
      |> Enum.map(fn day -> Map.put(totals(Map.get(by_day, day, [])), :day, day) end)

    %{series: series, totals: totals(day_groups)}
  end

  @doc "Gross, refunds, net, order count and average order value of order groups."
  def totals(groups) do
    gross = sum(groups, :gross_cents)
    refunds = sum(groups, :refunded_cents)
    orders = sum(groups, :orders)

    %{
      gross_cents: gross,
      refunded_cents: refunds,
      net_cents: gross - refunds,
      orders: orders,
      average_order_value_cents: average(gross - refunds, orders)
    }
  end

  @doc "Top products and variants by net revenue and by net units, `limit` each."
  def top_products(line_groups, limit \\ 10) do
    variants = Enum.map(line_groups, &variant_row/1)

    products =
      line_groups
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {product_id, groups} ->
        groups
        |> line_totals()
        |> Map.merge(%{product_id: product_id, product_name: hd(groups).product_name})
      end)

    %{
      products_by_revenue: top(products, :net_revenue_cents, limit),
      products_by_units: top(products, :net_units, limit),
      variants_by_revenue: top(variants, :net_revenue_cents, limit),
      variants_by_units: top(variants, :net_units, limit)
    }
  end

  @doc """
  Margin per product over the sales whose cost price is known, and how much
  of the revenue that covers (`cost_coverage_percent`). Sales without a cost
  stay out of cost and margin; they are never counted as free.
  """
  def margin(line_groups) do
    products =
      line_groups
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {product_id, groups} ->
        groups
        |> margin_totals()
        |> Map.merge(%{product_id: product_id, product_name: hd(groups).product_name})
      end)
      |> Enum.filter(&(&1.costed_revenue_cents > 0 or &1.cost_cents > 0))
      |> Enum.sort_by(&{-&1.margin_cents, &1.product_name || ""})

    %{totals: margin_totals(line_groups), products: products}
  end

  @doc "Order groups by channel and by branch, largest net first."
  def channels(channel_groups, location_groups) do
    %{
      by_channel: rank_groups(channel_groups, :channel),
      by_location: rank_groups(location_groups, :location_id)
    }
  end

  @doc """
  Stock on hand, stock value at cost (variants with a known cost), the
  low-stock list and sell-through per variant and in total. Sell-through is
  `sold / (sold + on hand)` over the report window.
  """
  def inventory(stock) do
    rows = Enum.map(stock, &stock_row/1)
    sold = sum(rows, :sold_units)
    on_hand = sum(rows, :on_hand)

    %{
      totals: %{
        on_hand: on_hand,
        reserved: sum(rows, :reserved),
        stock_value_cents: rows |> Enum.map(&(&1.stock_value_cents || 0)) |> Enum.sum(),
        uncosted_variants: Enum.count(rows, &is_nil(&1.unit_cost_cents)),
        low_stock_count: Enum.count(rows, & &1.low_stock),
        sold_units: sold,
        sell_through_percent: percent(sold, sold + on_hand)
      },
      low_stock:
        rows
        |> Enum.filter(& &1.low_stock)
        |> Enum.sort_by(&{&1.on_hand, &1.product_name || "", &1.variant_name || ""}),
      items: Enum.sort_by(rows, &{&1.product_name || "", &1.variant_name || "", &1.location_id})
    }
  end

  @doc """
  Sales attributed to a promotion code, a campaign or a source (a club feed
  post, the public page...). `source` groups carry `source` and
  `source_ref_id`; the `direct` source and orders without a code are the
  unattributed rest.
  """
  def attribution(code_groups, campaign_groups, source_groups) do
    {direct, attributed_sources} = Enum.split_with(source_groups, &(&1.source in [nil, "direct"]))

    %{
      by_promotion_code: rank_groups(code_groups, :promotion_code),
      by_campaign: rank_groups(campaign_groups, :campaign_id),
      by_source:
        attributed_sources
        |> Enum.map(fn group ->
          group
          |> List.wrap()
          |> totals()
          |> Map.merge(Map.take(group, [:source, :source_ref_id]))
        end)
        |> Enum.sort_by(&{-&1.net_cents, &1.source}),
      attributed: totals(attributed_sources),
      unattributed: totals(direct)
    }
  end

  ## Helpers

  defp rank_groups(groups, key) do
    groups
    |> Enum.group_by(&Map.get(&1, key))
    |> Enum.map(fn {value, group} -> Map.put(totals(group), key, value) end)
    |> Enum.sort_by(&{-&1.net_cents, to_string(Map.get(&1, key))})
  end

  defp variant_row(group) do
    group
    |> List.wrap()
    |> line_totals()
    |> Map.merge(Map.take(group, [:variant_id, :variant_name, :product_id, :product_name]))
  end

  defp line_totals(groups) do
    units = sum(groups, :units)
    refunded_units = sum(groups, :refunded_units)
    revenue = sum(groups, :revenue_cents)
    refunded = sum(groups, :refunded_cents)

    %{
      units: units,
      refunded_units: refunded_units,
      net_units: units - refunded_units,
      revenue_cents: revenue,
      refunded_cents: refunded,
      net_revenue_cents: revenue - refunded
    }
  end

  defp margin_totals(groups) do
    net_revenue = sum(groups, :revenue_cents) - sum(groups, :refunded_cents)
    costed = sum(groups, :costed_revenue_cents)
    cost = sum(groups, :cost_cents)

    %{
      net_revenue_cents: net_revenue,
      costed_revenue_cents: costed,
      uncosted_revenue_cents: net_revenue - costed,
      cost_cents: cost,
      margin_cents: costed - cost,
      margin_percent: percent(costed - cost, costed),
      cost_coverage_percent: percent(costed, net_revenue)
    }
  end

  defp stock_row(item) do
    on_hand = max(item.on_hand || 0, 0)
    sold = max(item.sold_units || 0, 0)

    %{
      variant_id: item.variant_id,
      product_id: item.product_id,
      product_name: item.product_name,
      variant_name: item.variant_name,
      location_id: item.location_id,
      on_hand: on_hand,
      reserved: item[:reserved] || 0,
      available: on_hand - (item[:reserved] || 0),
      unit_cost_cents: item.unit_cost_cents,
      stock_value_cents: stock_value(on_hand, item.unit_cost_cents),
      low_stock_threshold: item.low_stock_threshold,
      low_stock: low_stock?(on_hand, item.low_stock_threshold),
      sold_units: sold,
      sell_through_percent: percent(sold, sold + on_hand)
    }
  end

  defp stock_value(on_hand, cost) when is_integer(cost), do: on_hand * cost
  defp stock_value(_on_hand, _cost), do: nil

  defp low_stock?(on_hand, threshold) when is_integer(threshold), do: on_hand <= threshold
  defp low_stock?(_on_hand, _threshold), do: false

  defp top(rows, key, limit) do
    rows
    |> Enum.sort_by(
      &{-Map.fetch!(&1, key), &1.product_name || "", Map.get(&1, :variant_name) || ""}
    )
    |> Enum.take(limit)
  end

  defp sum(rows, key), do: Enum.reduce(rows, 0, &(&2 + (Map.get(&1, key) || 0)))

  # Half-up integer division: an average of cents is still whole cents.
  defp average(_total, 0), do: 0
  defp average(total, count) when total >= 0, do: div(2 * total + count, 2 * count)
  defp average(total, count), do: -average(-total, count)

  defp percent(_part, 0), do: nil
  defp percent(part, whole), do: Float.round(part * 100 / whole, 1)
end
