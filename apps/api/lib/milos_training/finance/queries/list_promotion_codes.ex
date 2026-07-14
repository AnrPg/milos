defmodule MilosTraining.Finance.Queries.ListPromotionCodes do
  alias MilosTraining.Finance.FinanceStore

  def call(campaign_id), do: FinanceStore.list_promotion_codes(campaign_id)
end
