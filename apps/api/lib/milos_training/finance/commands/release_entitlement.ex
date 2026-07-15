defmodule MilosTraining.Finance.Commands.ReleaseEntitlement do
  alias MilosTraining.Finance.FinanceStore
  def call(reservation_id, params), do: FinanceStore.release_entitlement(reservation_id, params)
end
