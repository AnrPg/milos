defmodule MilosTraining.Finance.Queries.ListPromotionCampaigns do
  alias MilosTraining.Finance.FinanceStore

  def call, do: FinanceStore.list_promotion_campaigns()
end
