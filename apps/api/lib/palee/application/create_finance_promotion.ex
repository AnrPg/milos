defmodule Palee.Application.CreateFinancePromotion do
  alias Palee.Application.CoveringBranches
  alias Palee.Finance

  def call(params), do: Finance.create_promotion_campaign(params)

  @doc "ADR-186 §8: a promotion is valid at the chosen branches (inside the scope)."
  def call(context, params) do
    with {:ok, target} <- CoveringBranches.for_new(context, CoveringBranches.requested(params)) do
      Finance.create_promotion_campaign(context, CoveringBranches.put_columns(params, target))
    end
  end
end
