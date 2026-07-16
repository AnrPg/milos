defmodule MilosTraining.Finance.Commands.RetirePackage do
  alias MilosTraining.Finance.FinanceStore

  def call(package_id, replacement_package_by_role),
    do: FinanceStore.retire_package(package_id, replacement_package_by_role)
end
