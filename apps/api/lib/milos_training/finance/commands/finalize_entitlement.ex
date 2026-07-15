defmodule MilosTraining.Finance.Commands.FinalizeEntitlement do
  alias MilosTraining.Finance.FinanceStore
  def call(reservation_id, params), do: FinanceStore.finalize_entitlement(reservation_id, params)
end
