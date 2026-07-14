defmodule MilosTraining.Finance.Queries.OperationalQueues do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.operational_queues(params)
end
