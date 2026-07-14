defmodule MilosTraining.Application.CreateFinancePromotionCode do
  alias MilosTraining.Finance

  def call(campaign_id, params), do: Finance.create_promotion_code(campaign_id, params)
end
