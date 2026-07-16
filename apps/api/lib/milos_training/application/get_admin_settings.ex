defmodule MilosTraining.Application.GetAdminSettings do
  alias MilosTraining.{Finance, Gamification, Notifications}

  def call do
    {:ok,
     %{
       gamification: Gamification.get_settings(),
       finance: Finance.get_finance_settings(),
       notifications: Notifications.get_push_settings()
     }}
  end
end
