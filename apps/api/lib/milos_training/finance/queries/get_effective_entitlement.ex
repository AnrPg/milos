defmodule MilosTraining.Finance.Queries.GetEffectiveEntitlement do
  alias MilosTraining.Finance.FinanceStore
  def call(user_id), do: FinanceStore.get_effective_entitlement(user_id)
end
