defmodule Palee.Perks.Domain.CodeImport do
  @moduledoc """
  The codes of a CSV the partner sent (ADR-191 §2, code pool), pure: the
  first column of every line, quotes undone, blank lines and a header
  (`code`, `codes`, `κωδικός`) skipped. Separators `,` `;` and tab are all
  accepted, as spreadsheets export them.
  """

  @headers ~w(code codes coupon κωδικός κωδικοί)
  @max_bytes 1_000_000

  def max_bytes, do: @max_bytes

  @doc "`{:ok, codes}` or `{:error, :invalid_perk_codes}`."
  def parse(csv) when is_binary(csv) and byte_size(csv) <= @max_bytes do
    codes =
      csv
      |> String.replace_prefix("﻿", "")
      |> String.split(~r/\r\n|\n|\r/)
      |> Enum.map(&first_cell/1)
      |> Enum.reject(&(&1 == ""))
      |> drop_header()

    if codes == [], do: {:error, :invalid_perk_codes}, else: {:ok, codes}
  end

  def parse(_csv), do: {:error, :invalid_perk_codes}

  defp first_cell(line) do
    line = String.trim(line)

    case line do
      "\"" <> rest ->
        rest |> String.split(~r/"(?!")/, parts: 2) |> hd() |> String.replace("\"\"", "\"")

      _plain ->
        line |> String.split([",", ";", "\t"], parts: 2) |> hd() |> String.trim()
    end
  end

  defp drop_header([first | rest]) do
    if String.downcase(first) in @headers, do: rest, else: [first | rest]
  end

  defp drop_header([]), do: []
end
