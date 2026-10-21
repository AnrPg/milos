defmodule Palee.Finance.Commands.UpdatePackage do
  alias Palee.Finance.FinanceStore

  def call(id, params), do: FinanceStore.update_package(id, params)
end
