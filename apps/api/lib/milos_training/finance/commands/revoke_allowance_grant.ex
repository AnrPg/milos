defmodule MilosTraining.Finance.Commands.RevokeAllowanceGrant do
  alias MilosTraining.Finance.FinanceStore

  def call(user_id, admin_id, grant_id, params),
    do: FinanceStore.revoke_allowance_grant(user_id, admin_id, grant_id, params)
end
