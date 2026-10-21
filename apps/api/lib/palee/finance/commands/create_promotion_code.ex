defmodule Palee.Finance.Commands.CreatePromotionCode do
  alias Palee.Finance.FinanceStore

  def call(campaign_id, params), do: FinanceStore.create_promotion_code(campaign_id, params)
end
