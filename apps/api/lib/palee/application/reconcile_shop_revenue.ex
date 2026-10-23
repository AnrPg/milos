defmodule Palee.Application.ReconcileShopRevenue do
  @moduledoc """
  The shop's daily revenue reconciliation (ADR-192 §5): for each gym-local
  business day, shop order totals == Finance's shop-stream invoice lines ==
  shop payments minus refunds, to the cent.

  `call/3` checks a business for a range of days (all branches), emits
  `[:palee, :shop, :reconciliation, :checked]`, logs one structured warning
  per drifting day and returns the verdict. The nightly
  `Palee.Workers.ShopRevenueReconciliationJob` runs it for every active
  business over the last `@lookback_days` days, because a refund changes the
  day of the sale it refunds; staff can run it on demand through the report
  API, and tests call it directly.

  The runbook is `docs/operations/shop-revenue-reconciliation.md`.
  """

  require Logger

  alias Palee.Organizations
  alias Palee.Shop.Domain.RevenueReconciliation
  alias Palee.Shop.ShopReportStore
  alias Palee.TimeZones.ZonedTime

  @lookback_days 7
  @max_days 366
  @read_capabilities [:view_business_analytics, :view_finance_reports, :manage_shop]

  def lookback_days, do: @lookback_days

  @doc """
  Reconciles `from..to` (gym-local dates). Options: `:emit` (default true)
  sends telemetry and logs drift.
  """
  def call(
        %{organization_id: organization_id} = context,
        %Date{} = from,
        %Date{} = to,
        opts \\ []
      )
      when is_binary(organization_id) do
    if Date.compare(from, to) == :gt or Date.diff(to, from) >= @max_days do
      {:error, :invalid_report_window}
    else
      zone = Organizations.organization_timezone(organization_id)

      filters = %{
        from_at: ZonedTime.start_of_day(from, zone),
        to_at: ZonedTime.start_of_day(Date.add(to, 1), zone),
        zone: zone,
        location_ids: nil
      }

      figures = ShopReportStore.reconciliation_figures(context, filters)

      result =
        figures.orders
        |> RevenueReconciliation.compare(figures.invoice_lines, figures.payments)
        |> Map.merge(%{from: from, to: to, time_zone: zone})

      if Keyword.get(opts, :emit, true), do: report(organization_id, result)
      {:ok, result}
    end
  end

  @doc "The nightly run for one business: the last `lookback_days` days, ending yesterday."
  def nightly(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    today = ZonedTime.local_date(now, Organizations.organization_timezone(organization_id))
    call(context, Date.add(today, -@lookback_days), Date.add(today, -1))
  end

  @doc "On demand, for staff: `days` (default 7) ending today, or `from`/`to`."
  def on_demand(context, params, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context),
         {:ok, from, to} <- range(context, params || %{}, now) do
      call(context, from, to, emit: false)
    end
  end

  defp range(context, params, now) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    today =
      ZonedTime.local_date(now, Organizations.organization_timezone(context.organization_id))

    case params do
      %{"from" => from, "to" => to} when is_binary(from) and is_binary(to) ->
        with {:ok, from} <- Date.from_iso8601(from), {:ok, to} <- Date.from_iso8601(to) do
          {:ok, from, to}
        else
          _invalid -> {:error, :invalid_report_window}
        end

      _days ->
        case Integer.parse(to_string(params["days"] || @lookback_days)) do
          {days, ""} when days in 1..@max_days -> {:ok, Date.add(today, 1 - days), today}
          _invalid -> {:error, :invalid_report_window}
        end
    end
  end

  defp report(organization_id, result) do
    :telemetry.execute(
      [:palee, :shop, :reconciliation, :checked],
      %{
        days: length(result.days),
        drifted_days: length(result.drifted),
        drift_cents: result.drift_cents
      },
      %{result: if(result.ok, do: "ok", else: "drift")}
    )

    Enum.each(result.drifted, fn day ->
      Logger.warning("shop_revenue_drift",
        event: "shop_revenue_drift",
        organization_id: organization_id,
        day: Date.to_iso8601(day.day),
        currency: day.currency,
        orders_cents: day.orders_cents,
        invoice_lines_cents: day.invoice_lines_cents,
        payments_cents: day.payments_cents,
        drift_cents: day.drift_cents
      )
    end)
  end

  defp authorize(context) do
    if Enum.any?(@read_capabilities, &Organizations.can?(context, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end
end
