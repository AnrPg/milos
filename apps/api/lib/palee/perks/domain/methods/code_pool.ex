defmodule Palee.Perks.Domain.Methods.CodePool do
  @moduledoc """
  A batch of single-use codes the partner gave (pasted or a CSV, topped up
  later), one per claim (ADR-191 §2). `low_pool_threshold` (default 10)
  raises the low-pool alert when the free codes drop to it.
  """
  @behaviour Palee.Perks.Domain.RedemptionMethod

  @default_threshold 10

  def default_threshold, do: @default_threshold

  @impl true
  def key, do: "code_pool"

  @impl true
  def validate(settings) do
    case Map.get(settings, :low_pool_threshold) do
      nil -> []
      n when is_integer(n) and n >= 0 and n <= 100_000 -> []
      _bad -> [low_pool_threshold: "must be between 0 and 100000"]
    end
  end

  @impl true
  def issue, do: :pool
  @impl true
  def verifiable?, do: false

  @impl true
  def ready(%{free_codes: free}) when free > 0, do: :ok
  def ready(_facts), do: {:error, :perk_codes_required}

  @impl true
  def reveal(_settings, code), do: %{code: code, url: nil, show_membership: false}

  @doc "Whether `free` codes left is at or under the alert threshold."
  def low?(settings, free),
    do: free <= (Map.get(settings, :low_pool_threshold) || @default_threshold)
end
