defmodule Palee.Identity.Domain.RecoveryCodes do
  @moduledoc """
  ADR-187: one-time recovery codes a person keeps offline. Ten codes of ten
  characters from an alphabet without look-alikes (no 0/o, 1/l/i), shown as
  `xxxxx-xxxxx`. Only their hashes are stored; typing is forgiving about
  case, spaces and dashes. Pure apart from the random source.
  """

  @count 10
  @alphabet ~c"23456789abcdefghjkmnpqrstuvwxyz"

  def count, do: @count

  def generate do
    for _index <- 1..@count do
      code =
        for <<byte <- :crypto.strong_rand_bytes(10)>>,
          into: "",
          do: <<Enum.at(@alphabet, rem(byte, length(@alphabet)))>>

      String.slice(code, 0, 5) <> "-" <> String.slice(code, 5, 5)
    end
  end

  def normalize(code) when is_binary(code),
    do: code |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

  def normalize(_code), do: ""

  def hash(code), do: :crypto.hash(:sha256, normalize(code))
end
