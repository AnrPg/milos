defmodule Palee.Finance.Commands.RefreshAggregates do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.refresh_aggregates()
end
