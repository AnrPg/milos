defmodule Palee.Finance.Commands.ReserveEntitlement do
  alias Palee.Finance.FinanceStore
  def call(user_id, request), do: FinanceStore.reserve_entitlement(user_id, request)
end
