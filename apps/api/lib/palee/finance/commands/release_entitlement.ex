defmodule Palee.Finance.Commands.ReleaseEntitlement do
  alias Palee.Finance.FinanceStore
  def call(reservation_id, params), do: FinanceStore.release_entitlement(reservation_id, params)
end
