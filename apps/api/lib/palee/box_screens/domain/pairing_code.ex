defmodule Palee.BoxScreens.Domain.PairingCode do
  @moduledoc """
  The pairing code («Κωδικός σύνδεσης», ADR-253) staff read on their phone
  and type on the TV: 8 characters shown as `ABCD-EFGH`, from an alphabet
  without look-alikes (no 0/O/D/Q, 1/I/L, 2/Z, 5/S, 8/B, U/V), valid for 15
  minutes. Only its SHA-256 is stored. Typing is forgiving: case, spaces
  and dashes do not matter.

  21 symbols and 8 places give about 3.8 × 10¹⁰ codes; with at most a few
  hundred live at once and pairing limited to 10 tries a minute per
  address, guessing one is not practical.
  """

  @alphabet ~c"ACEFGHJKMNPRTWXY34679"
  @length 8
  @valid_minutes 15

  def alphabet, do: List.to_string(@alphabet)
  def valid_minutes, do: @valid_minutes

  @doc "A new random code, formatted `ABCD-EFGH`."
  def generate do
    @length
    |> random_symbols([])
    |> List.to_string()
    |> format()
  end

  # Rejection sampling: bytes past the last whole multiple of the alphabet's
  # size are dropped, so every symbol is equally likely.
  @limit div(256, length(@alphabet)) * length(@alphabet)

  defp random_symbols(0, acc), do: acc

  defp random_symbols(missing, acc) do
    picked =
      missing
      |> Kernel.*(2)
      |> :crypto.strong_rand_bytes()
      |> :binary.bin_to_list()
      |> Enum.filter(&(&1 < @limit))
      |> Enum.take(missing)
      |> Enum.map(&Enum.at(@alphabet, rem(&1, length(@alphabet))))

    random_symbols(missing - length(picked), acc ++ picked)
  end

  @doc "When a code issued at `now` stops working."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @valid_minutes * 60, :second)

  @doc "The canonical 8 characters of what was typed, or `:error`."
  def normalize(value) when is_binary(value) do
    code = value |> String.upcase() |> String.replace(~r/[\s\-_.]/u, "")

    if String.length(code) == @length and
         code |> String.to_charlist() |> Enum.all?(&(&1 in @alphabet)),
       do: {:ok, code},
       else: :error
  end

  def normalize(_value), do: :error

  @doc "SHA-256 of a code (formatted or typed), or `:error`."
  def hash(value) do
    with {:ok, code} <- normalize(value), do: {:ok, :crypto.hash(:sha256, code)}
  end

  defp format(code), do: String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
end
