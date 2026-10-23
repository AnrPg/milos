defmodule Palee.Shop.Domain.PickupCode do
  @moduledoc """
  The short code a buyer shows at the desk to collect an order (ADR-190),
  separate from the order id and number: six characters from an alphabet
  without look-alikes (no 0/O, 1/I/L, 2/Z, 5/S, 8/B), so it reads aloud
  and types easily. Unique per business; the store draws again on a clash.
  """

  @alphabet ~c"ACDEFGHJKMNPQRTUVWXY34679"
  @length 6

  def length, do: @length

  @doc "A code from `random_bytes` (one byte per character)."
  @spec from_bytes(binary()) :: String.t()
  def from_bytes(<<bytes::binary-size(@length), _rest::binary>>) do
    size = Kernel.length(@alphabet)
    for <<byte <- bytes>>, into: "", do: <<Enum.at(@alphabet, rem(byte, size))>>
  end

  @doc "A fresh random code."
  def generate, do: from_bytes(:crypto.strong_rand_bytes(@length))

  @doc "A typed code as stored: trimmed, upper case, without spaces or dashes."
  def normalize(code) when is_binary(code),
    do: code |> String.upcase() |> String.replace(~r/[\s-]+/, "")

  def normalize(_code), do: nil

  @doc "Whether `code` could be a pickup code (shape only)."
  def valid?(code) when is_binary(code),
    do: byte_size(code) == @length and Enum.all?(String.to_charlist(code), &(&1 in @alphabet))

  def valid?(_code), do: false
end
