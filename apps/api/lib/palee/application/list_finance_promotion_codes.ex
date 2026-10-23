defmodule Palee.Application.ListFinancePromotionCodes do
  alias Palee.Application.ListFinancePromotions
  alias Palee.Finance

  def call(campaign_id), do: {:ok, %{promotion_codes: Finance.list_promotion_codes(campaign_id)}}

  def call(context, campaign_id) do
    with :ok <- ListFinancePromotions.authorize(context, campaign_id),
         do: {:ok, %{promotion_codes: Finance.list_promotion_codes(context, campaign_id)}}
  end
end
