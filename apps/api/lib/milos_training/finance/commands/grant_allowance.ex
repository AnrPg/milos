defmodule MilosTraining.Finance.Commands.GrantAllowance do
  alias MilosTraining.Finance.FinanceStore
  def call(user_id, admin_id, params), do: FinanceStore.grant_allowance(user_id, admin_id, params)
end
