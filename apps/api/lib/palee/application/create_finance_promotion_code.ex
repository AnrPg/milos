defmodule Palee.Application.CreateFinancePromotionCode do
  alias Palee.Finance

  def call(campaign_id, params), do: Finance.create_promotion_code(campaign_id, params)
end
