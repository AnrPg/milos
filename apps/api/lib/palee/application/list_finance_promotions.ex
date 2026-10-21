defmodule Palee.Application.ListFinancePromotions do
  alias Palee.Finance

  def call, do: {:ok, %{promotion_campaigns: Finance.list_promotion_campaigns()}}
end
