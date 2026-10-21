defmodule Palee.Finance.Queries.GetEntitlement do
  alias Palee.Finance.FinanceStore

  def call(user_id), do: FinanceStore.get_entitlement(user_id)
end
