defmodule MilosTraining.Finance.Commands.RefreshAggregates do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.refresh_aggregates()
end
