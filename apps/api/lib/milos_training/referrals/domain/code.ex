defmodule MilosTraining.Referrals.Domain.Code do
  @moduledoc """
  Invite codes (ADR-156): 8 characters of Crockford base32, which has no
  I, L, O or U, so a code read aloud or typed from a poster survives the
  usual mix-ups (O→0, I/L→1) and case. 32⁸ ≈ 10¹² codes keep guessing
  pointless behind the public lookup's rate limit.
  """

  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @length 8

  @doc "A fresh random code."
  def generate do
    for <<byte <- :crypto.strong_rand_bytes(@length)>>, into: "" do
      <<Enum.at(@alphabet, rem(byte, 32))>>
    end
  end

  @doc """
  The canonical form of what someone typed or scanned: `{:ok, code}`, or
  `:error` when it can't be a code.
  """
  def normalize(input) when is_binary(input) do
    code =
      input
      |> String.upcase()
      |> String.replace(~r/[\s\-_]/u, "")
      |> String.replace("O", "0")
      |> String.replace(["I", "L"], "1")

    if valid?(code), do: {:ok, code}, else: :error
  end

  def normalize(_input), do: :error

  def valid?(code) when is_binary(code),
    do: byte_size(code) == @length and code |> to_charlist() |> Enum.all?(&(&1 in @alphabet))

  def valid?(_code), do: false
end
