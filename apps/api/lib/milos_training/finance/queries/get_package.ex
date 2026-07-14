defmodule MilosTraining.Finance.Queries.GetPackage do
  alias MilosTraining.Finance.FinanceStore

  def call(id), do: FinanceStore.get_package(id)
end
