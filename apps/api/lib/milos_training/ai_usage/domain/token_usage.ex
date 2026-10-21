defmodule MilosTraining.AiUsage.Domain.TokenUsage do
  @moduledoc """
  Billable token counts of one model call (ADR-152), normalized from the
  provider's usage report so every count is billed exactly once:

    * `input_tokens` – prompt tokens billed at the input rate (the prompt,
      including tool results sent back, minus what was served from cache);
    * `cached_input_tokens` – prompt tokens served from the context cache
      (implicit or explicit), billed at the cache rate;
    * `output_tokens` – visible answer tokens (text, JSON, function calls);
    * `thinking_tokens` – reasoning tokens, billed at the output rate.
  """

  @enforce_keys [:input_tokens, :cached_input_tokens, :output_tokens, :thinking_tokens]
  defstruct input_tokens: 0, cached_input_tokens: 0, output_tokens: 0, thinking_tokens: 0

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          cached_input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          thinking_tokens: non_neg_integer()
        }

  @fields [:input_tokens, :cached_input_tokens, :output_tokens, :thinking_tokens]

  def fields, do: @fields

  def zero,
    do: %__MODULE__{input_tokens: 0, cached_input_tokens: 0, output_tokens: 0, thinking_tokens: 0}

  @doc """
  Reads a Gemini `usageMetadata` object. `promptTokenCount` already includes
  `cachedContentTokenCount`; `toolUsePromptTokenCount` (built-in tools) is
  billed as input; `thoughtsTokenCount` is billed as output. Returns `nil`
  when the response carried no usage report.
  """
  def from_gemini(%{} = usage) do
    prompt = count(usage, "promptTokenCount") + count(usage, "toolUsePromptTokenCount")
    cached = min(count(usage, "cachedContentTokenCount"), prompt)

    %__MODULE__{
      input_tokens: prompt - cached,
      cached_input_tokens: cached,
      output_tokens: count(usage, "candidatesTokenCount"),
      thinking_tokens: count(usage, "thoughtsTokenCount")
    }
  end

  def from_gemini(_missing), do: nil

  @doc """
  Reads an Anthropic Messages API `usage` object (ADR-174).
  `input_tokens` excludes cached tokens; `cache_read_input_tokens` are billed
  at the cache rate; `cache_creation_input_tokens` (cache writes) are billed
  here at the input rate, a slight under-count we accept since the advisor
  sends no cache breakpoints. Thinking is part of `output_tokens` and billed
  at the output rate, so `thinking_tokens` stays 0. Returns `nil` when the
  response carried no usage report.
  """
  def from_anthropic(%{} = usage) do
    %__MODULE__{
      input_tokens: count(usage, "input_tokens") + count(usage, "cache_creation_input_tokens"),
      cached_input_tokens: count(usage, "cache_read_input_tokens"),
      output_tokens: count(usage, "output_tokens"),
      thinking_tokens: 0
    }
  end

  def from_anthropic(_missing), do: nil

  def total(%__MODULE__{} = usage),
    do:
      usage.input_tokens + usage.cached_input_tokens + usage.output_tokens + usage.thinking_tokens

  def add(%__MODULE__{} = left, %__MODULE__{} = right) do
    Enum.reduce(@fields, left, fn field, acc ->
      Map.update!(acc, field, &(&1 + Map.fetch!(right, field)))
    end)
  end

  def sum(usages), do: Enum.reduce(usages, zero(), &add(&2, &1))

  def to_map(%__MODULE__{} = usage), do: Map.take(usage, @fields)

  def from_map(%{} = map) do
    struct!(__MODULE__, Map.new(@fields, &{&1, non_negative(Map.get(map, &1))}))
  end

  defp count(usage, key), do: non_negative(Map.get(usage, key))

  defp non_negative(value) when is_integer(value) and value > 0, do: value
  defp non_negative(_value), do: 0
end
