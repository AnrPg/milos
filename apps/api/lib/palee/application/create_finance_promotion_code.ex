defmodule Palee.Application.CreateFinancePromotionCode do
  alias Palee.Application.ListFinancePromotions
  alias Palee.Finance

  def call(campaign_id, params), do: Finance.create_promotion_code(campaign_id, params)

  @doc "ADR-186 §8: codes are added only to promotions inside the acting branches."
  def call(context, campaign_id, params) do
    with :ok <- ListFinancePromotions.authorize(context, campaign_id, true),
         do: Finance.create_promotion_code(context, campaign_id, params)
  end
end
