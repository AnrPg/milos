defmodule Palee.Finance.Queries.GetEffectiveEntitlement do
  alias Palee.Finance.FinanceStore
  def call(user_id), do: FinanceStore.get_effective_entitlement(user_id)
end
