defmodule MilosTraining.Application.GetAdminFinanceSummary do
  alias MilosTraining.Finance

  def call, do: {:ok, Finance.financial_summary()}
end
