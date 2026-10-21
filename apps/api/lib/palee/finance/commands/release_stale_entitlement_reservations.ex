defmodule Palee.Finance.Commands.ReleaseStaleEntitlementReservations do
  alias Palee.Finance.FinanceStore

  def call(cutoff), do: FinanceStore.release_stale_entitlement_reservations(cutoff)
end
