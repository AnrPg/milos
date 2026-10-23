defmodule Palee.Application.ShopReports do
  @moduledoc """
  The shop's reports and pricing indicators (ADR-192 §4, §6), shaped for a
  future «Κατάστημα › Αναλυτικά» tab.

  Every report takes the same window and branch filter:

    * `days` (1..366, default 30) ending today, or `from` / `to` (ISO dates,
      inclusive, at most 366 days) - gym-local days (ADR-176);
    * `location_ids` - branches, narrowed to the person's branch scope
      (ADR-186 §7). Shop facts carry their own branch (the order's pickup or
      desk branch, the stock's branch), so the filter applies to it directly.

  Access: the business analytics capability (ADR-099). Reads aggregate in
  the database (`ShopReportStore`); the maths is pure
  (`SalesReport`, `PricingIndicators`).
  """

  alias Palee.Organizations
  alias Palee.Shop.Domain.{PricingIndicators, SalesReport}
  alias Palee.Shop.ShopReportStore
  alias Palee.TimeZones.ZonedTime

  @read_capabilities [:view_business_analytics, :manage_shop]
  @write_capabilities [:manage_shop, :manage_settings]
  @default_days 30
  @max_days 366
  @top_limit 10
  @max_top_limit 50

  @doc "Headline KPIs of the window: sales, basket, refunds, margin and stock."
  def overview(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      day_groups = ShopReportStore.sales_by_day(context, window.filters)
      lines = ShopReportStore.line_groups(context, window.filters)
      stock = ShopReportStore.stock(context, window.filters)
      totals = SalesReport.totals(day_groups)
      margin = SalesReport.margin(lines).totals
      units = Enum.reduce(lines, 0, &(&2 + &1.units - &1.refunded_units))
      inventory = SalesReport.inventory(stock).totals

      {:ok,
       envelope(window, %{
         kpis:
           Map.merge(totals, %{
             units_sold: units,
             units_per_order: ratio(units, totals.orders),
             refund_rate_percent: percent(totals.refunded_cents, totals.gross_cents),
             margin_cents: margin.margin_cents,
             margin_percent: margin.margin_percent,
             cost_coverage_percent: margin.cost_coverage_percent,
             stock_on_hand: inventory.on_hand,
             stock_value_cents: inventory.stock_value_cents,
             low_stock_count: inventory.low_stock_count,
             sell_through_percent: inventory.sell_through_percent
           })
       })}
    end
  end

  @doc "Gross, refunds, net, orders and AOV per gym-local day, with totals."
  def sales(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      groups = ShopReportStore.sales_by_day(context, window.filters)

      {:ok, envelope(window, SalesReport.sales(groups, window.from, window.to))}
    end
  end

  @doc "Top products and variants by revenue and units."
  def products(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      lines = ShopReportStore.line_groups(context, window.filters)
      {:ok, envelope(window, SalesReport.top_products(lines, limit(params)))}
    end
  end

  @doc "Revenue, cost and margin where the cost price is known."
  def margin(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      lines = ShopReportStore.line_groups(context, window.filters)
      {:ok, envelope(window, SalesReport.margin(lines))}
    end
  end

  @doc "Sales by channel (online pickup or desk) and by branch."
  def channels(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      channel = ShopReportStore.order_groups(context, window.filters, :channel)
      location = ShopReportStore.order_groups(context, window.filters, :location_id)
      {:ok, envelope(window, SalesReport.channels(channel, location))}
    end
  end

  @doc "Stock on hand, stock value, low stock and sell-through."
  def inventory(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      stock = ShopReportStore.stock(context, window.filters)
      {:ok, envelope(window, SalesReport.inventory(stock))}
    end
  end

  @doc "Sales attributed to promotion codes, campaigns and sources (feed posts...)."
  def attribution(context, params, now \\ DateTime.utc_now()) do
    with {:ok, window} <- window(context, params, now) do
      codes = ShopReportStore.order_groups(context, window.filters, :promotion_code)
      campaigns = ShopReportStore.order_groups(context, window.filters, :campaign_id)
      sources = ShopReportStore.order_groups(context, window.filters, :source)
      {:ok, envelope(window, SalesReport.attribution(codes, campaigns, sources))}
    end
  end

  @doc """
  Pricing indicators per variant (margin, markup, velocity, stock cover,
  price-change effects, discount effect, elasticity, category bands) and an
  advisory suggested price range. Default window 90 days.
  """
  def pricing(context, params, now \\ DateTime.utc_now()) do
    params = Map.put_new(stringify(params), "days", "90")

    with {:ok, window} <- window(context, params, now) do
      inputs = ShopReportStore.pricing_inputs(context, window.filters)
      targets = ShopReportStore.pricing_targets(context)
      days = Date.diff(window.to, window.from) + 1

      {:ok, envelope(window, PricingIndicators.analyse(inputs, targets, days))}
    end
  end

  @doc "The target margins per category (`category: nil` is the box-wide default)."
  def pricing_targets(context) do
    with :ok <- authorize(context, @read_capabilities) do
      {:ok, %{targets: targets_payload(ShopReportStore.pricing_targets(context))}}
    end
  end

  @doc """
  Sets the target margin of a category (`category` nil or absent = the
  default) in basis points (0..9500) or percent (`target_margin_percent`,
  at most two decimals); `null` clears it.
  """
  def put_pricing_target(context, params) do
    params = stringify(params)

    with :ok <- authorize(context, @write_capabilities),
         {:ok, category} <- category(params["category"]),
         {:ok, target_bp} <- target_bp(params) do
      case ShopReportStore.put_pricing_target(
             context,
             category,
             target_bp,
             Map.get(context, :user_id)
           ) do
        :ok -> pricing_targets(context)
        {:error, _reason} -> {:error, :invalid_pricing_target}
      end
    end
  end

  ## Window

  @doc false
  def window(context, params, now) do
    params = stringify(params)

    with :ok <- authorize(context, @read_capabilities),
         zone = Organizations.organization_timezone(context.organization_id),
         today = ZonedTime.local_date(now, zone),
         {:ok, from, to} <- dates(params, today) do
      locations =
        case Organizations.report_filter(context, Organizations.requested_location_ids(params)) do
          :all -> nil
          ids -> ids
        end

      {:ok,
       %{
         from: from,
         to: to,
         zone: zone,
         location_ids: locations,
         filters: %{
           from_at: ZonedTime.start_of_day(from, zone),
           to_at: ZonedTime.start_of_day(Date.add(to, 1), zone),
           zone: zone,
           location_ids: locations
         }
       }}
    end
  end

  defp dates(%{"from" => from, "to" => to}, _today) when is_binary(from) and is_binary(to) do
    with {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to),
         true <- Date.compare(from, to) != :gt,
         true <- Date.diff(to, from) < @max_days do
      {:ok, from, to}
    else
      _invalid -> {:error, :invalid_report_window}
    end
  end

  defp dates(params, today) do
    case parse_days(params["days"]) do
      {:ok, days} -> {:ok, Date.add(today, 1 - days), today}
      :error -> {:error, :invalid_report_window}
    end
  end

  defp parse_days(nil), do: {:ok, @default_days}
  defp parse_days(days) when is_integer(days) and days in 1..@max_days, do: {:ok, days}

  defp parse_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> parse_days(value)
      _invalid -> :error
    end
  end

  defp parse_days(_days), do: :error

  defp envelope(window, report) do
    Map.merge(report, %{
      window: %{
        from: window.from,
        to: window.to,
        time_zone: window.zone,
        location_ids: window.location_ids
      }
    })
  end

  defp limit(params) do
    case Integer.parse(to_string(stringify(params)["limit"] || @top_limit)) do
      {value, ""} when value in 1..@max_top_limit -> value
      _default -> @top_limit
    end
  end

  defp category(nil), do: {:ok, nil}
  defp category(""), do: {:ok, nil}

  defp category(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.length(trimmed) in 1..80,
      do: {:ok, trimmed},
      else: {:error, :invalid_pricing_target}
  end

  defp category(_value), do: {:error, :invalid_pricing_target}

  defp target_bp(%{"target_margin_bp" => nil}), do: {:ok, nil}

  defp target_bp(%{"target_margin_bp" => bp}) when is_integer(bp) and bp in 0..9_500,
    do: {:ok, bp}

  defp target_bp(%{"target_margin_percent" => nil}), do: {:ok, nil}

  defp target_bp(%{"target_margin_percent" => percent})
       when is_binary(percent) or is_number(percent) do
    # Decimal, never a float, so "37.5" is exactly 3_750 basis points.
    with {:ok, decimal} <- to_decimal(percent),
         bp = Decimal.mult(decimal, 100),
         true <- Decimal.integer?(bp) || :not_whole,
         value = Decimal.to_integer(bp),
         true <- value in 0..9_500 do
      {:ok, value}
    else
      _invalid -> {:error, :invalid_pricing_target}
    end
  end

  defp target_bp(_params), do: {:error, :invalid_pricing_target}

  defp to_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp to_decimal(value) when is_float(value),
    do: {:ok, Decimal.from_float(value) |> Decimal.round(4)}

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> {:ok, decimal}
      _invalid -> :error
    end
  end

  defp targets_payload(targets) do
    default = PricingIndicators.default_target_margin_bp()

    targets
    |> Enum.map(fn {category, bp} -> %{category: category, target_margin_bp: bp} end)
    |> then(fn rows ->
      if Enum.any?(rows, &is_nil(&1.category)),
        do: rows,
        else: [%{category: nil, target_margin_bp: default, implicit: true} | rows]
    end)
    |> Enum.sort_by(&{not is_nil(&1.category), &1.category || ""})
  end

  defp authorize(context, capabilities) do
    if Enum.any?(capabilities, &Organizations.can?(context, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp ratio(_part, 0), do: nil
  defp ratio(part, whole), do: Float.round(part / whole, 2)

  defp percent(_part, 0), do: nil
  defp percent(part, whole), do: Float.round(part * 100 / whole, 1)

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_params), do: %{}
end
