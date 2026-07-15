defmodule MilosTraining.Finance.Domain.AllowancePeriod do
  @moduledoc "Pure calculation of inclusive allowance period boundaries."

  def bounds(:calendar_week, %Date{} = date, _subscription) do
    start_date = Date.add(date, 1 - Date.day_of_week(date))
    {start_date, Date.add(start_date, 6)}
  end

  def bounds(:calendar_month, %Date{} = date, _subscription) do
    start_date = Date.beginning_of_month(date)
    {start_date, Date.end_of_month(date)}
  end

  def bounds(:subscription_period, %Date{} = date, subscription) do
    starts_on = Map.get(subscription, :starts_on) || Map.get(subscription, "starts_on") || date
    ends_on = Map.get(subscription, :ends_on) || Map.get(subscription, "ends_on") || date
    {starts_on, ends_on}
  end
end
