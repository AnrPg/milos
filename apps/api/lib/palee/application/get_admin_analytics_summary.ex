defmodule Palee.Application.GetAdminAnalyticsSummary do
  alias Palee.{Analytics, Coaching, Execution, Feedback, Finance, Wellbeing}

  # TD-092: every summary reads tenant facts, so the whole dashboard is built
  # in the gym's scope. Unscoped, each read was empty under the production
  # runtime role and the dashboard showed zeros.
  def call(context, params) do
    Analytics.with_tenant_context(context, fn -> build(params) end)
  end

  defp build(params) do
    analytics = Analytics.analytics_summary(params)
    finance = Finance.financial_summary(params)
    coaching = Coaching.get_aggregates()
    feedback = Feedback.review_summary(params)
    wellbeing = Wellbeing.injury_summary(params)
    execution = Execution.execution_kpis(since(params))

    {:ok,
     %{
       dashboard: dashboard_view(analytics, finance, coaching, feedback, wellbeing),
       analytics: analytics,
       finance: finance,
       coaching: coaching,
       feedback: feedback,
       wellbeing: wellbeing,
       execution: execution
     }}
  end

  @default_days 30

  # Same window the other summaries use (`days`, default 30).
  defp since(params) do
    days =
      case params[:days] || params["days"] do
        days when is_integer(days) and days > 0 -> days
        days when is_binary(days) -> parse_days(days)
        _ -> @default_days
      end

    DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
  end

  defp parse_days(value) do
    case Integer.parse(value) do
      {days, ""} when days > 0 -> days
      _ -> @default_days
    end
  end

  defp dashboard_view(analytics, finance, coaching, feedback, wellbeing) do
    %{
      finance: %{
        active_memberships: get_in(finance, [:totals, :active_memberships]) || 0,
        expiring_memberships: get_in(finance, [:totals, :expiring_memberships]) || 0,
        paid_revenue_cents: get_in(finance, [:totals, :paid_revenue_cents]) || 0,
        credit_balance_cents: get_in(finance, [:totals, :credit_balance_cents]) || 0,
        aggregate_status: finance[:aggregate_status] || "unknown"
      },
      coaching: coaching,
      cross_context: %{
        event_count: get_in(analytics, [:events, :total]) || 0,
        review_count: feedback[:total] || 0,
        low_rating_count: feedback[:low_rating_count] || 0,
        injury_count: wellbeing[:total] || 0,
        active_injury_count: wellbeing[:active_count] || 0
      }
    }
  end
end
