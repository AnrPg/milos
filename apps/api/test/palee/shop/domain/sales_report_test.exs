defmodule Palee.Shop.Domain.SalesReportTest do
  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.SalesReport

  @d1 ~D[2026-12-14]
  @d2 ~D[2026-12-15]

  defp group(attrs),
    do: Map.merge(%{orders: 1, gross_cents: 1_000, refunded_cents: 0}, Map.new(attrs))

  defp line(attrs) do
    Map.merge(
      %{
        product_id: "p1",
        product_name: "Shaker",
        variant_id: "v1",
        variant_name: "Black",
        units: 1,
        refunded_units: 0,
        revenue_cents: 1_000,
        refunded_cents: 0,
        costed_revenue_cents: 0,
        cost_cents: 0
      },
      Map.new(attrs)
    )
  end

  test "sales fills every day, nets refunds and rounds the average half up" do
    groups = [
      group(day: @d1, orders: 2, gross_cents: 3_001, refunded_cents: 500),
      group(day: @d2, orders: 1, gross_cents: 3_000)
    ]

    %{series: [first, second], totals: totals} = SalesReport.sales(groups, @d1, @d2)

    assert first == %{
             day: @d1,
             gross_cents: 3_001,
             refunded_cents: 500,
             net_cents: 2_501,
             orders: 2,
             average_order_value_cents: 1_251
           }

    assert second.net_cents == 3_000
    assert totals.net_cents == 5_501
    assert totals.orders == 3

    assert [%{orders: 0, average_order_value_cents: 0}] =
             SalesReport.sales([], @d1, @d1).series
  end

  test "top products rank by net revenue and net units" do
    lines = [
      line(variant_id: "v1", units: 3, revenue_cents: 3_000),
      line(variant_id: "v2", variant_name: "Red", units: 1, revenue_cents: 1_000),
      line(product_id: "p2", product_name: "Protein", variant_id: "v3", revenue_cents: 5_000)
    ]

    report = SalesReport.top_products(lines, 5)

    assert [%{product_id: "p2", net_revenue_cents: 5_000}, %{product_id: "p1"}] =
             report.products_by_revenue

    assert [%{product_id: "p1", net_units: 4} | _] = report.products_by_units
    assert [%{variant_id: "v3"} | _] = report.variants_by_revenue
    assert [%{variant_id: "v1", net_units: 3} | _] = report.variants_by_units
  end

  test "margin only counts sales with a known cost" do
    lines = [
      line(units: 2, revenue_cents: 2_000, costed_revenue_cents: 2_000, cost_cents: 800),
      line(product_id: "p2", product_name: "Bar", variant_id: "v9", revenue_cents: 500)
    ]

    %{totals: totals, products: [product]} = SalesReport.margin(lines)

    assert totals.net_revenue_cents == 2_500
    assert totals.costed_revenue_cents == 2_000
    assert totals.uncosted_revenue_cents == 500
    assert totals.cost_cents == 800
    assert totals.margin_cents == 1_200
    assert totals.margin_percent == 60.0
    assert totals.cost_coverage_percent == 80.0
    assert product.product_id == "p1"
  end

  test "channels rank by net" do
    %{by_channel: channels, by_location: locations} =
      SalesReport.channels(
        [group(channel: "online"), group(channel: "pos", gross_cents: 2_000)],
        [group(location_id: "loc-a"), group(location_id: "loc-b", gross_cents: 2_000)]
      )

    assert [%{channel: "pos", net_cents: 2_000}, %{channel: "online"}] = channels
    assert Enum.map(locations, & &1.location_id) == ["loc-b", "loc-a"]
  end

  test "inventory values stock at cost and lists low stock" do
    stock = [
      %{
        variant_id: "v1",
        product_id: "p1",
        product_name: "Shaker",
        variant_name: "Black",
        location_id: "loc-a",
        on_hand: 2,
        reserved: 1,
        unit_cost_cents: 300,
        low_stock_threshold: 3,
        sold_units: 6
      },
      %{
        variant_id: "v2",
        product_id: "p1",
        product_name: "Shaker",
        variant_name: "Red",
        location_id: "loc-a",
        on_hand: 10,
        reserved: 0,
        unit_cost_cents: nil,
        low_stock_threshold: nil,
        sold_units: 0
      }
    ]

    %{totals: totals, low_stock: [low]} = SalesReport.inventory(stock)

    assert low.variant_id == "v1"
    assert low.available == 1
    assert low.sell_through_percent == 75.0
    assert totals.on_hand == 12
    assert totals.reserved == 1
    assert totals.stock_value_cents == 600
    assert totals.uncosted_variants == 1
    assert totals.low_stock_count == 1
    assert totals.sell_through_percent == 33.3
  end

  test "attribution separates codes, campaigns, sources and the direct rest" do
    report =
      SalesReport.attribution(
        [group(promotion_code: "SUMMER", gross_cents: 2_000)],
        [group(campaign_id: "c1", gross_cents: 2_000)],
        [
          group(source: "promotion_code", source_ref_id: nil, gross_cents: 2_000),
          group(source: "club_post", source_ref_id: "post-1"),
          group(source: "direct", source_ref_id: nil, gross_cents: 700)
        ]
      )

    assert [%{promotion_code: "SUMMER", net_cents: 2_000}] = report.by_promotion_code
    assert [%{campaign_id: "c1"}] = report.by_campaign

    assert [
             %{source: "promotion_code", net_cents: 2_000},
             %{source: "club_post", source_ref_id: "post-1", orders: 1}
           ] = report.by_source

    assert report.attributed.net_cents == 3_000
    assert report.unattributed.net_cents == 700
  end
end
