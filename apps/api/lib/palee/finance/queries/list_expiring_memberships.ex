defmodule Palee.Finance.Queries.ListExpiringMemberships do
  alias Palee.Finance.FinanceStore

  def call(days), do: FinanceStore.list_expiring_memberships(days)
end
