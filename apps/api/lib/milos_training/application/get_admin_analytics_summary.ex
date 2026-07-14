defmodule MilosTraining.Application.GetAdminAnalyticsSummary do
  alias MilosTraining.{Analytics, Coaching, Feedback, Finance, Wellbeing}

  def call(params \\ %{}) do
    analytics = Analytics.analytics_summary(params)
    finance = Finance.financial_summary(params)
    coaching = Coaching.get_aggregates()
    feedback = Feedback.review_summary(params)
    wellbeing = Wellbeing.injury_summary(params)

    {:ok,
     %{
       dashboard: dashboard_view(analytics, finance, coaching, feedback, wellbeing),
       analytics: analytics,
       finance: finance,
       coaching: coaching,
       feedback: feedback,
       wellbeing: wellbeing
     }}
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
