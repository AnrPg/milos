defmodule Palee.Application.GetAdminAnalyticsSummary do
  alias Palee.Application.BranchReport
  alias Palee.{Analytics, Coaching, Execution, Feedback, Finance, Wellbeing}

  # TD-092: every summary reads tenant facts, so the whole dashboard is built
  # in the gym's scope. Unscoped, each read was empty under the production
  # runtime role and the dashboard showed zeros.
  #
  # ADR-186 §7: `location_ids` narrows every figure to some branches: located
  # facts by their branch, the rest by the people whose home branch it is.
  def call(context, params) do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
    report = BranchReport.resolve(context, params)
    scoped = BranchReport.scope_params(params, report)

    with {:ok, payload} <-
           Analytics.with_tenant_context(context, fn -> build(context, scoped, report) end) do
      {:ok,
       payload
       |> Map.put(:branch_filter, BranchReport.filter_payload(report))
       |> Map.put(:branches, branches(context, report, params))}
    end
  end

  defp build(context, params, report) do
    analytics = Analytics.analytics_summary(params)
    finance = Finance.financial_summary(params)
    coaching = Coaching.get_aggregates(context, report.user_ids)
    feedback = Feedback.review_summary(params)
    wellbeing = Wellbeing.injury_summary(params)
    execution = Execution.execution_kpis(since(params), report.user_ids)

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

  # Headline figures per branch: its people, their payments and reviews, and
  # the check-ins and attended classes at the branch in the window.
  defp branches(context, report, params) do
    activity = BranchReport.activity_by_branch(context, since(params))

    BranchReport.splits(context, report, fn users, location_id ->
      finance = Finance.financial_summary(context, Map.put(params, "user_ids", users)).totals
      visits = Map.get(activity, location_id, %{check_ins: 0, attended: 0})

      %{
        check_ins: visits.check_ins,
        attended: visits.attended,
        active_memberships: finance.active_memberships,
        paid_revenue_cents: finance.paid_revenue_cents
      }
    end)
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
