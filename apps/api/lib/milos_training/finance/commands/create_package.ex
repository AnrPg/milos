defmodule MilosTraining.Finance.Commands.CreatePackage do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.create_package(params)
end
