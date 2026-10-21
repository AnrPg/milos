defmodule Palee.Finance.Queries.GetMemberProfile do
  alias Palee.Finance.FinanceStore

  def call(user_id), do: FinanceStore.get_member_profile(user_id)
end
