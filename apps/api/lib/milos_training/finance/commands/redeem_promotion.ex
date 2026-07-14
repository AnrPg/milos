defmodule MilosTraining.Finance.Commands.RedeemPromotion do
  alias MilosTraining.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.redeem_promotion(membership_id, params)
end
