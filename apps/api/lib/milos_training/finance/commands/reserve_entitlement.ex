defmodule MilosTraining.Finance.Commands.ReserveEntitlement do
  alias MilosTraining.Finance.FinanceStore
  def call(user_id, request), do: FinanceStore.reserve_entitlement(user_id, request)
end
