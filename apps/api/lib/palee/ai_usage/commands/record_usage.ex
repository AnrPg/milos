defmodule Palee.AiUsage.Commands.RecordUsage do
  @moduledoc """
  Persists one billed model call for the tenant in `context` (ADR-152),
  priced at the list price in force on the day of the call. A model missing
  from the price list is still recorded, with no cost, so it shows up as
  unpriced in reports instead of silently costing nothing.
  """

  alias Palee.AiUsage.AiUsageStore
  alias Palee.AiUsage.Domain.{PriceList, TokenUsage}

  def call(%{organization_id: organization_id} = context, %{usage: %TokenUsage{} = usage} = attrs)
      when is_binary(organization_id) do
    record =
      attrs
      |> Map.delete(:usage)
      |> Map.merge(TokenUsage.to_map(usage))
      |> Map.put(:cost_nano_usd, cost(usage, attrs))

    AiUsageStore.insert_record(context, record)
  end

  def call(_context, _attrs), do: {:error, :invalid_usage}

  defp cost(usage, %{model: model, occurred_at: %DateTime{} = occurred_at}) do
    case PriceList.cost(usage, model, DateTime.to_date(occurred_at)) do
      {:ok, nano} -> nano
      {:error, :unpriced_model} -> nil
    end
  end

  defp cost(_usage, _attrs), do: nil
end
