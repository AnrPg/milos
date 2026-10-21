defmodule Palee.Finance.Queries.ListPromotionCodes do
  alias Palee.Finance.FinanceStore

  def call(campaign_id), do: FinanceStore.list_promotion_codes(campaign_id)
end
