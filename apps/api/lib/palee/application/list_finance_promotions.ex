defmodule Palee.Application.ListFinancePromotions do
  alias Palee.Application.{BranchReport, CoveringBranches}
  alias Palee.Finance

  def call, do: {:ok, %{promotion_campaigns: Finance.list_promotion_campaigns()}}

  @doc """
  ADR-186 §8: branch staff see the promotions valid at one of their
  branches. With `location_ids` (§7) only the promotions valid at one of the
  chosen branches, or everywhere, stay.
  """
  def call(context, params \\ %{}) do
    report = BranchReport.resolve_list(context, params)

    campaigns =
      context
      |> CoveringBranches.visible(
        Finance.list_promotion_campaigns(context),
        &CoveringBranches.of_row/1
      )
      |> BranchReport.covering_only(report, &CoveringBranches.of_row/1)

    {:ok, %{promotion_campaigns: campaigns, branch_filter: BranchReport.filter_payload(report)}}
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
