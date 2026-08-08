defmodule MilosTraining.Application.GetAdminSettings do
  alias MilosTraining.{Finance, Gamification, Notifications, Scheduling}

  def call, do: {:error, :organization_context_required}

  def call(context) do
    {:ok,
     %{
       gamification: Gamification.get_settings(),
       finance: Finance.get_finance_settings(),
       notifications: Notifications.get_push_settings(),
       scheduling: Scheduling.get_settings(context)
     }}
  end
end
