defmodule MilosTraining.Finance.Queries.FinancialSummary do
  alias MilosTraining.Finance.FinanceStore

  def call(params \\ %{}), do: FinanceStore.financial_summary(params)
end
