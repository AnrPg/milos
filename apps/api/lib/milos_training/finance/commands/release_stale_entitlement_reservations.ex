defmodule MilosTraining.Finance.Commands.ReleaseStaleEntitlementReservations do
  alias MilosTraining.Finance.FinanceStore

  def call(cutoff), do: FinanceStore.release_stale_entitlement_reservations(cutoff)
end
