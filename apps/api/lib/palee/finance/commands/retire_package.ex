defmodule Palee.Finance.Commands.RetirePackage do
  alias Palee.Finance.FinanceStore

  def call(package_id, replacement_package_by_role),
    do: FinanceStore.retire_package(package_id, replacement_package_by_role)
end
