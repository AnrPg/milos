defmodule Palee.Application.CreateFinancePromotion do
  alias Palee.Finance

  def call(params), do: Finance.create_promotion_campaign(params)
end
