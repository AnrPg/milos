defmodule MilosTraining.Application.CreateFinancePromotion do
  alias MilosTraining.Finance

  def call(params), do: Finance.create_promotion_campaign(params)
end
