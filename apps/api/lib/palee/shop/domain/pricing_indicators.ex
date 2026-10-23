defmodule Palee.Shop.Domain.PricingIndicators do
  @moduledoc """
  Indicators that help a box put a price on an item (ADR-192 §6). Pure: no
  clock, no database; the report store hands over aggregates.

  Money is integer cents and every price this module produces is a whole
  number of cents (rounded half up, never below cost). Ratios and
  percentages are floats rounded to one or two decimals; they are reported,
  never fed back into money except through integer basis points.

  Everything here is **advisory**: the suggested range says so and lists
  the inputs and the reasoning behind it, so staff can see why.

  Inputs per variant (`variant`):

    * `:price_cents`, `:cost_cents` (nil when unknown), `:category`,
      `:on_hand`;
    * `:price_points` - `[%{price_cents, units, days}]`: units sold at each
      observed price inside the window and the days the variant was on sale
      at that price (from the price-history ledger);
    * `:periods` - `[%{price_cents, from, to, days, units}]`: the window cut at
      every price change, oldest first;
    * `:promo` / `:full_price` - `%{units, orders, list_cents, discount_cents}`
      for lines of orders with and without a promotion or discount.
  """

  @basis 10_000
  @default_target_margin_bp 4_000
  @max_target_margin_bp 9_500
  # Velocity relative to the category median that reads as fast or slow.
  @fast_ratio 1.5
  @slow_ratio 0.5
  # How far the suggested range moves for a fast or slow seller.
  @fast_uplift_bp 1_000
  @slow_cut_bp 500

  def default_target_margin_bp, do: @default_target_margin_bp

  ## The whole report

  @doc """
  Every indicator for every variant, plus the category bands. `targets`
  maps a category to its target margin in basis points (a `nil` key is the
  box-wide default); `window_days` is the report window.
  """
  def analyse(variants, targets, window_days) when is_integer(window_days) and window_days > 0 do
    variants = Enum.map(variants, &with_velocity(&1, window_days))
    bands = price_bands(variants)

    median_velocity =
      variants
      |> Enum.group_by(&(&1.category || "uncategorised"))
      |> Map.new(fn {category, items} ->
        {category,
         items |> Enum.map(& &1.velocity_per_week) |> Enum.reject(&is_nil/1) |> median()}
      end)

    rows =
      Enum.map(variants, fn variant ->
        category = variant.category || "uncategorised"
        units = sold_units(variant)
        elasticity = elasticity(variant[:price_points] || [])
        target = Map.get(targets, variant.category) || Map.get(targets, nil)

        %{
          variant_id: variant.variant_id,
          product_id: variant.product_id,
          product_name: variant.product_name,
          variant_name: variant.variant_name,
          category: category,
          price_cents: variant.price_cents,
          cost_cents: variant.cost_cents,
          margin_percent: margin_percent(variant.price_cents, variant.cost_cents),
          markup_percent: markup_percent(variant.price_cents, variant.cost_cents),
          on_hand: variant.on_hand,
          units_sold: units,
          velocity_per_week: variant.velocity_per_week,
          sell_through_percent: sell_through_percent(units, variant.on_hand || 0),
          days_on_sale: variant.days_on_sale,
          days_of_stock_left: days_of_stock_left(variant.on_hand, units, variant.days_on_sale),
          price_changes: price_change_effects(variant[:periods] || []),
          discount: discount_effect(variant[:promo], variant[:full_price]),
          elasticity: elasticity,
          band: band_position(variant.price_cents, Map.get(bands, category)),
          suggested_price:
            suggested_range(variant, target, Map.get(median_velocity, category), elasticity)
        }
      end)

    %{
      window_days: window_days,
      categories:
        bands
        |> Map.values()
        |> Enum.map(fn band ->
          Map.merge(band, %{
            median_velocity_per_week: Map.get(median_velocity, band.category),
            target_margin_bp:
              Map.get(targets, band.category) || Map.get(targets, nil) ||
                @default_target_margin_bp
          })
        end)
        |> Enum.sort_by(& &1.category),
      variants: Enum.sort_by(rows, &{&1.category, &1.product_name || "", &1.variant_name || ""})
    }
  end

  # A variant new to the shop has been on sale for less than the window: its
  # pace is over the days it was on sale (from the price ledger), capped by
  # the window.
  defp with_velocity(variant, window_days) do
    ledger_days = sum(variant[:price_points] || [], :days)
    days = if ledger_days > 0, do: min(ledger_days, window_days), else: window_days

    variant
    |> Map.put(:days_on_sale, days)
    |> Map.put(:velocity_per_week, velocity_per_week(sold_units(variant), days))
  end

  defp sold_units(variant), do: sum(variant[:price_points] || [], :units)

  ## Unit economics

  @doc "Margin on price, in percent: `(price - cost) / price`."
  def margin_percent(price, cost) when is_integer(price) and price > 0 and is_integer(cost),
    do: round1((price - cost) * 100 / price)

  def margin_percent(_price, _cost), do: nil

  @doc "Markup on cost, in percent: `(price - cost) / cost`."
  def markup_percent(price, cost) when is_integer(price) and is_integer(cost) and cost > 0,
    do: round1((price - cost) * 100 / cost)

  def markup_percent(_price, _cost), do: nil

  @doc """
  The price that earns `target_bp` basis points of margin over `cost`:
  `cost / (1 - target)`, rounded up to the next whole cent so the margin is
  never below target.
  """
  def cost_plus_price(cost, target_bp)
      when is_integer(cost) and cost >= 0 and is_integer(target_bp) and target_bp >= 0 and
             target_bp <= @max_target_margin_bp do
    ceil_div(cost * @basis, @basis - target_bp)
  end

  def cost_plus_price(_cost, _target_bp), do: nil

  ## Velocity and stock

  @doc "Units per week from units sold over `days` days."
  def velocity_per_week(units, days) when is_integer(units) and is_integer(days) and days > 0,
    do: Float.round(units * 7 / days, 2)

  def velocity_per_week(_units, _days), do: nil

  @doc "Whole days of stock left at the observed rate; nil when nothing sells."
  def days_of_stock_left(on_hand, units, days)
      when is_integer(on_hand) and is_integer(units) and units > 0 and is_integer(days) and
             days > 0,
      do: div(max(on_hand, 0) * days, units)

  def days_of_stock_left(_on_hand, _units, _days), do: nil

  @doc "Sell-through over the window: `sold / (sold + on hand)`, percent."
  def sell_through_percent(sold, on_hand) when is_integer(sold) and is_integer(on_hand) do
    whole = max(sold, 0) + max(on_hand, 0)
    if whole == 0, do: nil, else: round1(max(sold, 0) * 100 / whole)
  end

  @doc """
  Velocity before and after each price change inside the window, newest
  change first. A period of fewer than `min_days` days on either side is
  marked `:insufficient`, since a day or two says little.
  """
  def price_change_effects(periods, min_days \\ 7) do
    periods
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [before, after_change] ->
      before_velocity = velocity_per_week(before.units, before.days)
      after_velocity = velocity_per_week(after_change.units, after_change.days)

      %{
        changed_on: after_change.from,
        from_price_cents: before.price_cents,
        to_price_cents: after_change.price_cents,
        price_change_percent: change_percent(after_change.price_cents, before.price_cents),
        velocity_before: before_velocity,
        velocity_after: after_velocity,
        velocity_change_percent: change_percent(after_velocity, before_velocity),
        evidence:
          if(before.days >= min_days and after_change.days >= min_days,
            do: :sufficient,
            else: :insufficient
          )
      }
    end)
    |> Enum.reverse()
  end

  ## Discounts

  @doc """
  Discount depth (the share of list price given away on discounted sales)
  and its effect on volume: units per order and the share of units sold
  with a discount, against full-price sales.
  """
  def discount_effect(promo, full_price) do
    promo = normalize_sales(promo)
    full = normalize_sales(full_price)
    promo_per_order = per_order(promo)
    full_per_order = per_order(full)

    %{
      discount_depth_percent: percent(promo.discount_cents, promo.list_cents),
      discount_cents: promo.discount_cents,
      promo_units: promo.units,
      promo_orders: promo.orders,
      full_price_units: full.units,
      full_price_orders: full.orders,
      promo_units_per_order: promo_per_order,
      full_price_units_per_order: full_per_order,
      promo_unit_share_percent: percent(promo.units, promo.units + full.units),
      volume_lift_percent: change_percent(promo_per_order, full_per_order)
    }
  end

  ## Elasticity

  @doc """
  Price elasticity of demand from the observed price points: the slope of
  `ln(units per day)` on `ln(price)` by least squares. Needs at least two
  distinct prices with days on sale. Units get a +0.5 continuity correction
  so a price that sold nothing still counts as evidence.

  Confidence is `:high` (3+ prices, 30+ units, fit R² >= 0.6), `:medium`
  (10+ units and R² >= 0.3, or two prices and 20+ units), otherwise `:low`.
  """
  def elasticity(price_points) do
    points =
      price_points
      |> Enum.filter(&(is_integer(&1.price_cents) and &1.price_cents > 0 and &1.days > 0))
      |> Enum.group_by(& &1.price_cents)
      |> Enum.map(fn {price, group} ->
        %{price_cents: price, units: sum(group, :units), days: sum(group, :days)}
      end)

    if length(points) < 2 do
      %{estimate: nil, confidence: :none, price_points: length(points), reason: :too_few_prices}
    else
      xs = Enum.map(points, &:math.log(&1.price_cents))
      ys = Enum.map(points, &:math.log((&1.units + 0.5) / &1.days))
      {slope, r2} = least_squares(xs, ys)
      units = sum(points, :units)

      %{
        estimate: Float.round(slope, 2),
        r_squared: Float.round(r2, 2),
        confidence: confidence(length(points), units, r2),
        price_points: length(points),
        units: units,
        reading: reading(slope)
      }
    end
  end

  defp least_squares(xs, ys) do
    n = length(xs)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n
    sxx = xs |> Enum.map(&((&1 - mean_x) * (&1 - mean_x))) |> Enum.sum()
    sxy = Enum.zip(xs, ys) |> Enum.map(fn {x, y} -> (x - mean_x) * (y - mean_y) end) |> Enum.sum()
    syy = ys |> Enum.map(&((&1 - mean_y) * (&1 - mean_y))) |> Enum.sum()

    cond do
      sxx == 0.0 -> {0.0, 0.0}
      syy == 0.0 -> {0.0, 1.0}
      true -> {sxy / sxx, sxy * sxy / (sxx * syy)}
    end
  end

  defp confidence(points, units, r2) do
    cond do
      points >= 3 and units >= 30 and r2 >= 0.6 -> :high
      units >= 10 and r2 >= 0.3 and points >= 3 -> :medium
      points == 2 and units >= 20 -> :medium
      true -> :low
    end
  end

  defp reading(slope) when slope <= -1.0, do: :elastic
  defp reading(slope) when slope < 0.0, do: :inelastic
  defp reading(_slope), do: :no_price_sensitivity_seen

  ## Price bands

  @doc """
  The box's own price bands per category: count, min, quartiles, median and
  max of current prices (nearest-rank, whole cents).
  """
  def price_bands(variants) do
    variants
    |> Enum.filter(&is_integer(&1.price_cents))
    |> Enum.group_by(&(&1.category || "uncategorised"))
    |> Map.new(fn {category, items} ->
      prices = items |> Enum.map(& &1.price_cents) |> Enum.sort()

      {category,
       %{
         category: category,
         items: length(prices),
         min_cents: hd(prices),
         p25_cents: nearest_rank(prices, 25),
         median_cents: nearest_rank(prices, 50),
         p75_cents: nearest_rank(prices, 75),
         max_cents: List.last(prices)
       }}
    end)
  end

  @doc "Where a price sits in its category band."
  def band_position(_price, nil), do: nil

  def band_position(price, band) when is_integer(price) do
    position =
      cond do
        price < band.p25_cents -> :below_band
        price > band.p75_cents -> :above_band
        true -> :within_band
      end

    %{
      position: position,
      vs_median_cents: price - band.median_cents,
      vs_median_percent: change_percent(price, band.median_cents),
      similar_items: band.items - 1
    }
  end

  ## Suggested range

  @doc """
  An advisory price range: the cost-plus price at the category's target
  margin, widened up for a fast seller or down (never below cost-plus at
  zero margin, i.e. cost) for a slow one, relative to the category's median
  velocity. Elastic demand caps the upward move. Returns the range, its
  inputs and a plain explanation; `nil` range when the cost is unknown.
  """
  def suggested_range(variant, target_bp, category_median_velocity, elasticity) do
    cost = variant.cost_cents
    velocity = variant[:velocity_per_week]
    target = target_bp || @default_target_margin_bp

    inputs = %{
      cost_cents: cost,
      current_price_cents: variant.price_cents,
      target_margin_bp: target,
      target_margin_source: if(target_bp, do: :category_setting, else: :default),
      velocity_per_week: velocity,
      category_median_velocity_per_week: category_median_velocity,
      elasticity: elasticity && elasticity[:estimate],
      elasticity_confidence: elasticity && elasticity[:confidence]
    }

    case cost_plus_price(cost, target) do
      nil ->
        %{
          advisory: true,
          low_cents: nil,
          high_cents: nil,
          inputs: inputs,
          explanation: ["No cost price is recorded, so no cost-plus range can be computed."]
        }

      base ->
        {low, high, notes} = adjust(base, cost, velocity, category_median_velocity, elasticity)

        %{
          advisory: true,
          low_cents: low,
          high_cents: high,
          cost_plus_cents: base,
          inputs: inputs,
          explanation:
            [
              "Cost-plus at a #{format_bp(target)} margin gives #{base} cents " <>
                "(#{if target_bp, do: "the category's target", else: "the default target"})."
            ] ++ notes ++ ["Advisory only: the box sets its prices."]
        }
    end
  end

  defp adjust(base, cost, velocity, median, elasticity) do
    elastic? =
      is_map(elasticity) and elasticity[:reading] == :elastic and
        elasticity[:confidence] in [:medium, :high]

    case velocity_class(velocity, median) do
      :fast when elastic? ->
        {base, apply_bp(base, div(@fast_uplift_bp, 2)),
         [
           "It sells fast for its category, but demand looks price-sensitive, so the upward room is halved."
         ]}

      :fast ->
        {base, apply_bp(base, @fast_uplift_bp),
         [
           "It sells at least #{@fast_ratio}× its category's median pace, so there is room above cost-plus."
         ]}

      :slow ->
        {max(apply_bp(base, -@slow_cut_bp), cost), base,
         [
           "It sells at most #{@slow_ratio}× its category's median pace, so the range reaches below cost-plus (never below cost)."
         ]}

      :normal ->
        {base, apply_bp(base, div(@slow_cut_bp, 2)), ["It sells at about its category's pace."]}

      :unknown ->
        {base, base,
         ["There is not enough sales data to judge its pace, so the range is cost-plus alone."]}
    end
  end

  defp velocity_class(velocity, median)
       when is_number(velocity) and is_number(median) and median > 0 do
    ratio = velocity / median

    cond do
      ratio >= @fast_ratio -> :fast
      ratio <= @slow_ratio -> :slow
      true -> :normal
    end
  end

  defp velocity_class(_velocity, _median), do: :unknown

  @doc "The median of the numeric values (nil when none)."
  def median([]), do: nil

  def median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end

  ## Helpers

  defp normalize_sales(nil), do: %{units: 0, orders: 0, list_cents: 0, discount_cents: 0}

  defp normalize_sales(sales) do
    %{
      units: sales[:units] || 0,
      orders: sales[:orders] || 0,
      list_cents: sales[:list_cents] || 0,
      discount_cents: sales[:discount_cents] || 0
    }
  end

  defp per_order(%{orders: 0}), do: nil
  defp per_order(%{units: units, orders: orders}), do: Float.round(units / orders, 2)

  # Integer cents moved by `bp` basis points, rounded half up.
  defp apply_bp(cents, bp), do: div(2 * cents * (@basis + bp) + @basis, 2 * @basis)

  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp nearest_rank(sorted, pct) do
    rank = max(ceil_div(pct * length(sorted), 100), 1)
    Enum.at(sorted, rank - 1)
  end

  defp change_percent(new, old) when is_number(new) and is_number(old) and old != 0,
    do: round1((new - old) * 100 / old)

  defp change_percent(_new, _old), do: nil

  defp percent(_part, 0), do: nil
  defp percent(part, whole), do: round1(part * 100 / whole)

  defp round1(value), do: Float.round(value * 1.0, 1)

  defp format_bp(bp),
    do: "#{div(bp, 100)}.#{String.pad_leading(Integer.to_string(rem(bp, 100)), 2, "0")}%"

  defp sum(rows, key), do: Enum.reduce(rows, 0, &(&2 + (Map.get(&1, key) || 0)))
end
