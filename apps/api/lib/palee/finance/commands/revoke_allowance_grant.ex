defmodule Palee.Finance.Commands.RevokeAllowanceGrant do
  alias Palee.Finance.FinanceStore

  def call(user_id, admin_id, grant_id, params),
    do: FinanceStore.revoke_allowance_grant(user_id, admin_id, grant_id, params)
end
