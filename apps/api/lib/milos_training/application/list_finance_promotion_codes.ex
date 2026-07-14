defmodule MilosTraining.Application.ListFinancePromotionCodes do
  alias MilosTraining.Finance

  def call(campaign_id), do: {:ok, %{promotion_codes: Finance.list_promotion_codes(campaign_id)}}
end
