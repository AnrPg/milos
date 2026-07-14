defmodule MilosTraining.Application.ListFinancePromotions do
  alias MilosTraining.Finance

  def call, do: {:ok, %{promotion_campaigns: Finance.list_promotion_campaigns()}}
end
