defmodule MilosTraining.Finance.Queries.ListExpiringMemberships do
  alias MilosTraining.Finance.FinanceStore

  def call(days), do: FinanceStore.list_expiring_memberships(days)
end
