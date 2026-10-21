defmodule Palee.Finance.Commands.CreatePromotionCampaign do
  alias Palee.Finance.FinanceStore

  def call(params), do: FinanceStore.create_promotion_campaign(params)
end
