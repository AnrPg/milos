defmodule MilosTraining.Wellness.Domain.Water do
  @moduledoc """
  Νερό (ADR-159 §1): one drink, in millilitres. The member taps «+1» for one
  glass of their own size; the day total is the sum, and undo deletes the
  entry. Stored in ml so a new glass size or a device never rewrites history.
  """

  @behaviour MilosTraining.Wellness.Domain.EntryValue

  alias MilosTraining.Wellness.Domain.EntryValue

  @max_ml 3_000

  @impl true
  def cast(params) do
    case EntryValue.integer(params, "ml", 1, @max_ml) do
      {:ok, nil} -> {:error, %{"ml" => "is required"}}
      {:ok, ml} -> {:ok, %{"ml" => ml}}
      error -> error
    end
  end

  @impl true
  def counts_at(_value, occurred_at), do: occurred_at

  def ml(%{"ml" => ml}) when is_integer(ml), do: ml
  def ml(_value), do: 0
end
