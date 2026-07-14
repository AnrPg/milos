defmodule MilosTraining.Finance.Commands.UpsertMembership do
  alias MilosTraining.Finance.FinanceStore

  def call(user_id, params), do: FinanceStore.upsert_membership(user_id, params)
end
