defmodule Palee.Shop.Domain.PricingIndicatorsTest do
  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.PricingIndicators, as: P

  describe "unit economics" do
    test "margin and markup from cost" do
      assert P.margin_percent(2_000, 1_200) == 40.0
      assert P.markup_percent(2_000, 1_200) == 66.7
      assert P.margin_percent(2_000, nil) == nil
      assert P.markup_percent(2_000, 0) == nil
    end

    test "cost-plus rounds up to a whole cent so the margin is never short" do
      # 1_000 / (1 - 0.4) = 1666.67 -> 1667
      assert P.cost_plus_price(1_000, 4_000) == 1_667
      assert P.cost_plus_price(1_200, 4_000) == 2_000
      assert P.cost_plus_price(999, 0) == 999
      assert P.margin_percent(P.cost_plus_price(1_000, 4_000), 1_000) >= 40.0
      assert P.cost_plus_price(1_000, 10_000) == nil
      assert P.cost_plus_price(nil, 4_000) == nil
    end
  end

  describe "velocity and stock" do
    test "units per week, days of stock left and sell-through" do
      assert P.velocity_per_week(30, 30) == 7.0
      assert P.velocity_per_week(0, 0) == nil
      assert P.days_of_stock_left(10, 30, 30) == 10
      assert P.days_of_stock_left(10, 0, 30) == nil
      assert P.sell_through_percent(30, 10) == 75.0
      assert P.sell_through_percent(0, 0) == nil
    end

    test "price change effects compare the pace before and after, newest first" do
      periods = [
        %{price_cents: 2_000, from: ~D[2026-11-01], to: ~D[2026-11-14], days: 14, units: 28},
        %{price_cents: 2_500, from: ~D[2026-11-15], to: ~D[2026-11-28], days: 14, units: 14},
        %{price_cents: 2_200, from: ~D[2026-11-29], to: ~D[2026-11-30], days: 2, units: 2}
      ]

      [latest, first] = P.price_change_effects(periods)

      assert first.from_price_cents == 2_000
      assert first.to_price_cents == 2_500
      assert first.price_change_percent == 25.0
      assert first.velocity_before == 14.0
      assert first.velocity_after == 7.0
      assert first.velocity_change_percent == -50.0
      assert first.evidence == :sufficient
      assert latest.evidence == :insufficient
    end
  end

  test "discount depth and its effect on volume" do
    effect =
      P.discount_effect(
        %{units: 30, orders: 10, list_cents: 30_000, discount_cents: 6_000},
        %{units: 20, orders: 10, list_cents: 20_000, discount_cents: 0}
      )

    assert effect.discount_depth_percent == 20.0
    assert effect.promo_units_per_order == 3.0
    assert effect.full_price_units_per_order == 2.0
    assert effect.volume_lift_percent == 50.0
    assert effect.promo_unit_share_percent == 60.0
    assert P.discount_effect(nil, nil).discount_depth_percent == nil
  end

  describe "elasticity" do
    test "needs two prices" do
      assert %{estimate: nil, confidence: :none} =
               P.elasticity([%{price_cents: 1_000, units: 10, days: 10}])
    end

    test "falling sales at a higher price read as elastic with confidence from the evidence" do
      points = [
        %{price_cents: 1_000, units: 100, days: 30},
        %{price_cents: 1_200, units: 60, days: 30},
        %{price_cents: 1_400, units: 35, days: 30}
      ]

      result = P.elasticity(points)

      assert result.estimate < -1.0
      assert result.reading == :elastic
      assert result.confidence == :high
      assert result.price_points == 3
    end

    test "two prices and few units are low confidence" do
      result =
        P.elasticity([
          %{price_cents: 1_000, units: 3, days: 10},
          %{price_cents: 1_100, units: 2, days: 10}
        ])

      assert result.confidence == :low
      assert is_float(result.estimate)
    end
  end

  test "price bands are whole-cent nearest-rank quartiles per category" do
    variants =
      for {price, category} <- [
            {1_000, "apparel"},
            {2_000, "apparel"},
            {3_000, "apparel"},
            {4_000, "apparel"},
            {500, "food"}
          ],
          do: %{price_cents: price, category: category}

    bands = P.price_bands(variants)

    assert bands["apparel"] == %{
             category: "apparel",
             items: 4,
             min_cents: 1_000,
             p25_cents: 1_000,
             median_cents: 2_000,
             p75_cents: 3_000,
             max_cents: 4_000
           }

    assert %{position: :above_band, vs_median_cents: 2_000, similar_items: 3} =
             P.band_position(4_000, bands["apparel"])
  end

  describe "suggested range" do
    @variant %{price_cents: 2_000, cost_cents: 1_200}

    test "is advisory and explains a cost-plus range for a fast seller" do
      result =
        P.suggested_range(Map.put(@variant, :velocity_per_week, 10.0), 4_000, 5.0, nil)

      assert result.advisory
      assert result.cost_plus_cents == 2_000
      assert result.low_cents == 2_000
      assert result.high_cents == 2_200
      assert result.inputs.target_margin_source == :category_setting
      assert Enum.any?(result.explanation, &(&1 =~ "Advisory"))
    end

    test "a slow seller reaches below cost-plus but never below cost" do
      result = P.suggested_range(Map.put(@variant, :velocity_per_week, 1.0), 4_000, 5.0, nil)
      assert result.low_cents == 1_900
      assert result.high_cents == 2_000

      cheap = %{price_cents: 1_000, cost_cents: 1_000, velocity_per_week: 1.0}
      assert P.suggested_range(cheap, 0, 5.0, nil).low_cents == 1_000
    end

    test "elastic demand halves the upward room" do
      elastic = %{estimate: -2.0, reading: :elastic, confidence: :high}
      result = P.suggested_range(Map.put(@variant, :velocity_per_week, 10.0), 4_000, 5.0, elastic)
      assert result.high_cents == 2_100
    end

    test "falls back to the default target and says so; no cost means no range" do
      result = P.suggested_range(@variant, nil, nil, nil)
      assert result.inputs.target_margin_source == :default
      assert result.low_cents == result.high_cents

      assert %{low_cents: nil, advisory: true} =
               P.suggested_range(%{price_cents: 2_000, cost_cents: nil}, 4_000, nil, nil)
    end
  end

  test "analyse builds every indicator per variant and the category bands" do
    variants = [
      %{
        variant_id: "v1",
        product_id: "p1",
        product_name: "Shaker",
        variant_name: "Black",
        category: "gear",
        price_cents: 1_500,
        cost_cents: 600,
        on_hand: 20,
        price_points: [%{price_cents: 1_500, units: 30, days: 30}],
        periods: [],
        promo: nil,
        full_price: %{units: 30, orders: 30, list_cents: 45_000, discount_cents: 0}
      },
      %{
        variant_id: "v2",
        product_id: "p2",
        product_name: "Belt",
        variant_name: nil,
        category: "gear",
        price_cents: 4_000,
        cost_cents: nil,
        on_hand: 5,
        price_points: [%{price_cents: 4_000, units: 3, days: 15}],
        periods: [],
        promo: nil,
        full_price: nil
      }
    ]

    report = P.analyse(variants, %{"gear" => 5_000}, 30)

    assert [%{category: "gear", items: 2, target_margin_bp: 5_000}] = report.categories
    [belt, shaker] = report.variants

    assert shaker.margin_percent == 60.0
    assert shaker.velocity_per_week == 7.0
    assert shaker.days_of_stock_left == 20
    assert shaker.suggested_price.cost_plus_cents == 1_200
    assert belt.days_on_sale == 15
    assert belt.velocity_per_week == 1.4
    assert belt.suggested_price.low_cents == nil
  end
end
