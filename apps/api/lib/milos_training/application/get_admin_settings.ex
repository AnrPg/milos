defmodule MilosTraining.Application.GetAdminSettings do
  alias MilosTraining.{Finance, Gamification}

  def call do
    {:ok,
     %{
       gamification: Gamification.get_settings(),
       finance: Finance.get_finance_settings()
     }}
  end
end
