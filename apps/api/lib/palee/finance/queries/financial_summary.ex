defmodule Palee.Finance.Queries.FinancialSummary do
  alias Palee.Finance.FinanceStore

  def call(params \\ %{}), do: FinanceStore.financial_summary(params)
end
