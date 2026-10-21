defmodule Palee.AiUsage.Domain.PriceList do
  @moduledoc """
  Paid-tier list prices of the models Palee calls (ADR-152), dated so a call
  is always priced at the rate in force on the day it was made.

  Rates are nano-USD per token, which is the published USD-per-1M-tokens price
  × 1000 (e.g. $0.75 / 1M tokens = 750 nano-USD per token). Costs are integer
  nano-USD, exact for any price with up to three decimals.

  Source: https://ai.google.dev/gemini-api/docs/pricing (Standard tier, text
  input, read 2026-10-16). None of these models has prompt-length tiers.
  Claude models (ADR-174): https://platform.claude.com/docs/en/about-claude/pricing
  (standard tier, read 2026-10-21); cached input is the cache-read rate.

  Update this table whenever a provider changes a price: add a new dated entry,
  never edit a past one, so stored costs stay reproducible.
  """

  @type rates :: %{
          input: non_neg_integer(),
          cached_input: non_neg_integer(),
          output: non_neg_integer()
        }

  # model => [{effective_from, rates}], newest last.
  @prices %{
    "gemini-3.8-flash" => [
      {~D[2000-01-01], %{input: 750, cached_input: 75, output: 3_750}},
      {~D[2027-01-01], %{input: 1_500, cached_input: 150, output: 7_500}}
    ],
    "gemini-3.6-flash" => [
      {~D[2000-01-01], %{input: 750, cached_input: 75, output: 3_750}},
      {~D[2027-01-01], %{input: 1_500, cached_input: 150, output: 7_500}}
    ],
    "gemini-3-flash-preview" => [
      {~D[2000-01-01], %{input: 500, cached_input: 50, output: 3_000}}
    ],
    "gemini-3.5-flash-lite" => [
      {~D[2000-01-01], %{input: 300, cached_input: 30, output: 2_500}}
    ],
    "gemini-3.1-flash-lite" => [
      {~D[2000-01-01], %{input: 250, cached_input: 25, output: 1_500}}
    ],
    "gemini-2.5-flash" => [
      {~D[2000-01-01], %{input: 300, cached_input: 30, output: 2_500}}
    ],
    "gemini-2.5-flash-lite" => [
      {~D[2000-01-01], %{input: 100, cached_input: 10, output: 400}}
    ],
    "claude-sonnet-5-5" => [
      {~D[2000-01-01], %{input: 2_000, cached_input: 200, output: 10_000}}
    ],
    "claude-opus-5-5" => [
      {~D[2000-01-01], %{input: 4_000, cached_input: 200, output: 20_000}}
    ],
    "claude-haiku-5-5" => [
      {~D[2000-01-01], %{input: 100, cached_input: 10, output: 500}}
    ]
  }

  alias Palee.AiUsage.Domain.TokenUsage

  def models, do: Map.keys(@prices)

  @doc """
  The rates for `model` on `date`. `model` may be a versioned name the
  provider reports (`gemini-2.5-flash-lite-001`): the longest known model name
  it starts with is used.
  """
  def rates(model, %Date{} = date) when is_binary(model) do
    with {:ok, schedule} <- schedule(model) do
      schedule
      |> Enum.filter(fn {from, _rates} -> Date.compare(from, date) != :gt end)
      |> List.last()
      |> case do
        {_from, rates} -> {:ok, rates}
        nil -> {:error, :unpriced_model}
      end
    end
  end

  def rates(_model, _date), do: {:error, :unpriced_model}

  @doc "Cost of `usage` in integer nano-USD, or `{:error, :unpriced_model}`."
  def cost(%TokenUsage{} = usage, model, %Date{} = date) do
    with {:ok, rates} <- rates(model, date) do
      {:ok,
       usage.input_tokens * rates.input + usage.cached_input_tokens * rates.cached_input +
         (usage.output_tokens + usage.thinking_tokens) * rates.output}
    end
  end

  @doc "Nano-USD as a USD float, for display only (sums stay in nano-USD)."
  def to_usd(nano) when is_integer(nano), do: nano / 1_000_000_000
  def to_usd(nil), do: nil

  defp schedule(model) do
    case Map.fetch(@prices, model) do
      {:ok, schedule} ->
        {:ok, schedule}

      :error ->
        @prices
        |> Enum.filter(fn {name, _schedule} -> String.starts_with?(model, name <> "-") end)
        |> Enum.max_by(fn {name, _schedule} -> String.length(name) end, fn -> nil end)
        |> case do
          {_name, schedule} -> {:ok, schedule}
          nil -> {:error, :unpriced_model}
        end
    end
  end
end
