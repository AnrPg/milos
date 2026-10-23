defmodule Palee.Application.ListFinancePromotions do
  alias Palee.Application.CoveringBranches
  alias Palee.Finance

  def call, do: {:ok, %{promotion_campaigns: Finance.list_promotion_campaigns()}}

  @doc "ADR-186 §8: branch staff see the promotions valid at one of their branches."
  def call(context) do
    campaigns = Finance.list_promotion_campaigns(context)

    {:ok,
     %{
       promotion_campaigns:
         CoveringBranches.visible(context, campaigns, &CoveringBranches.of_row/1)
     }}
  end

  @doc "`:ok` when the acting staff see campaign `id` (`editable?` to change it)."
  def authorize(context, id, editable? \\ false) do
    case Enum.find(Finance.list_promotion_campaigns(context), &(&1.id == id)) do
      nil ->
        {:error, :not_found}

      campaign ->
        target = CoveringBranches.of_row(campaign)

        cond do
          editable? ->
            CoveringBranches.authorize(context, target)

          CoveringBranches.visible(context, [campaign], fn _ -> target end) == [] ->
            {:error, :not_found}

          true ->
            :ok
        end
    end
  end
end
