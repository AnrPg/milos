defmodule MilosTraining.Finance.Commands.CreatePromotionCampaign do
  alias MilosTraining.Finance.FinanceStore

  def call(params), do: FinanceStore.create_promotion_campaign(params)
end
