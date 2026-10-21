defmodule Palee.AiUsage.Queries.OperationUsage do
  @moduledoc """
  Every model call of one user action (ADR-152), e.g. the structure,
  proofreader, parser and repair calls of one free-text workout analysis,
  with their totals.
  """

  alias Palee.AiUsage.AiUsageStore
  alias Palee.AiUsage.Domain.{PriceList, TokenUsage}

  def call(context, operation_id) when is_binary(operation_id) do
    calls = AiUsageStore.list_operation(context, operation_id)
    usage = calls |> Enum.map(&TokenUsage.from_map/1) |> TokenUsage.sum()
    priced = Enum.reject(calls, &is_nil(&1.cost_nano_usd))

    %{
      operation_id: operation_id,
      calls: calls,
      usage: TokenUsage.to_map(usage),
      total_tokens: TokenUsage.total(usage),
      cost_nano_usd: Enum.sum(Enum.map(priced, & &1.cost_nano_usd)),
      cost_usd: PriceList.to_usd(Enum.sum(Enum.map(priced, & &1.cost_nano_usd))),
      unpriced_calls: length(calls) - length(priced)
    }
  end
end
