defmodule Palee.Finance.Commands.GrantAllowance do
  alias Palee.Finance.FinanceStore
  def call(user_id, admin_id, params), do: FinanceStore.grant_allowance(user_id, admin_id, params)
end
