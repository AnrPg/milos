defmodule Palee.Finance.Queries.OperationalQueues do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.operational_queues(params)
end
