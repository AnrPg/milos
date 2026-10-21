defmodule Palee.Finance.Queries.ListPackages do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.list_packages()
end
