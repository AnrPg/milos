defmodule MilosTraining.AiUsage.Queries.UsageSummary do
  @moduledoc """
  A tenant's AI usage over a period (ADR-152), per feature and model: user
  actions (operations), model calls, billed tokens and cost, with the mean
  cost per operation. Period bounds are `[from, to)`.
  """

  alias MilosTraining.AiUsage.AiUsageStore
  alias MilosTraining.AiUsage.Domain.PriceList

  def call(context, params \\ %{}) do
    rows = context |> AiUsageStore.summarize(params) |> Enum.map(&with_means/1)

    %{
      from: Map.get(params, :from),
      to: Map.get(params, :to),
      rows: rows,
      cost_nano_usd: Enum.sum(Enum.map(rows, & &1.cost_nano_usd)),
      cost_usd: PriceList.to_usd(Enum.sum(Enum.map(rows, & &1.cost_nano_usd)))
    }
  end

  defp with_means(%{operations: operations, cost_nano_usd: cost} = row) when operations > 0 do
    Map.merge(row, %{
      cost_usd: PriceList.to_usd(cost),
      mean_cost_per_operation_usd: PriceList.to_usd(cost) / operations
    })
  end

  defp with_means(row), do: Map.merge(row, %{cost_usd: 0.0, mean_cost_per_operation_usd: nil})
end
