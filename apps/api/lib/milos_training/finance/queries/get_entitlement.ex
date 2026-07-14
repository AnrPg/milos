defmodule MilosTraining.Finance.Queries.GetEntitlement do
  alias MilosTraining.Finance.FinanceStore

  def call(user_id), do: FinanceStore.get_entitlement(user_id)
end
