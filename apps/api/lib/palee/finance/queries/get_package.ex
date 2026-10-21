defmodule Palee.Finance.Queries.GetPackage do
  alias Palee.Finance.FinanceStore

  def call(id), do: FinanceStore.get_package(id)
end
