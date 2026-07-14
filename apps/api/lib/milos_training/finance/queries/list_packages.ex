defmodule MilosTraining.Finance.Queries.ListPackages do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.list_packages()
end
