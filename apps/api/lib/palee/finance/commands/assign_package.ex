defmodule Palee.Finance.Commands.AssignPackage do
  alias Palee.Finance.FinanceStore

  def call(membership_id, package_id, params),
    do: FinanceStore.assign_package(membership_id, package_id, params)
end
