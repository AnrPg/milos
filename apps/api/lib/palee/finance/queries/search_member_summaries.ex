defmodule Palee.Finance.Queries.SearchMemberSummaries do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.search_member_summaries(params)
end
