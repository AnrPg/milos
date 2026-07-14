defmodule MilosTraining.Finance.Commands.UpdatePackage do
  alias MilosTraining.Finance.FinanceStore

  def call(id, params), do: FinanceStore.update_package(id, params)
end
