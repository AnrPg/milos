defmodule Palee.Finance.Commands.UpsertMembership do
  alias Palee.Finance.FinanceStore

  def call(user_id, params), do: FinanceStore.upsert_membership(user_id, params)
end
