defmodule MilosTraining.Finance.Queries.SearchMemberSummaries do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.search_member_summaries(params)
end
