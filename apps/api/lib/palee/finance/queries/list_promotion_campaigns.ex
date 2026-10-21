defmodule Palee.Finance.Queries.ListPromotionCampaigns do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.list_promotion_campaigns()
end
