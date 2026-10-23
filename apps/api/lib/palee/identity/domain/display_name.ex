defmodule Palee.Identity.Domain.DisplayName do
  @moduledoc """
  ADR-187: the name a profile is shown by. Free and not unique: any script
  Unicode supports, emoji, capitals and spaces are kept exactly as typed
  (only NFC-normalized and trimmed). Control and invisible formatting
  characters are refused so a name cannot hide text or reorder its neighbours.
  Pure.
  """

  @max 50

  def max_length, do: @max

  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value
    |> String.normalize(:nfc)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def valid?(value) when is_binary(value) do
    normalized = normalize(value)

    String.length(normalized) in 1..@max and String.valid?(normalized) and
      not Regex.match?(
        ~r/[\p{Cc}\p{Co}\p{Cn}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u,
        normalized
      )
  end

  def valid?(_value), do: false
end
