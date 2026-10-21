defmodule Palee.Finance.Commands.RedeemPromotion do
  alias Palee.Finance.FinanceStore

  def call(membership_id, params), do: FinanceStore.redeem_promotion(membership_id, params)
end
