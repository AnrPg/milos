defmodule MilosTraining.Finance.Commands.CreatePromotionCode do
  alias MilosTraining.Finance.FinanceStore

  def call(campaign_id, params), do: FinanceStore.create_promotion_code(campaign_id, params)
end
