defmodule Palee.Finance.Commands.CreatePackage do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.create_package(params)
end
