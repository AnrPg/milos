defmodule Palee.Application.ListFinancePromotionCodes do
  alias Palee.Finance

  def call(campaign_id), do: {:ok, %{promotion_codes: Finance.list_promotion_codes(campaign_id)}}
end
