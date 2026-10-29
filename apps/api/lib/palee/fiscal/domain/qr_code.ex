defmodule Palee.Fiscal.Domain.QrCode do
  @moduledoc """
  QR code modules for printed fiscal documents (ADR-245): the Swiss
  QR-bill (error correction M, byte mode, UTF-8) and the myDATA link.
  Encoding is done by the `eqrcode` library; this module only returns the
  dark modules without the quiet zone, so renderers draw them as vector
  squares at any size.
  """

  @doc """
  `{:ok, %{size, dark}}`: `size` modules per side and the dark modules as
  `{column, row}` from the top-left corner. `{:error, :qr_too_long}` beyond
  what a QR code holds.
  """
  def modules(text, level \\ :m) when is_binary(text) do
    if byte_size(text) > 2_000 do
      {:error, :qr_too_long}
    else
      rows =
        text
        |> EQRCode.encode(level)
        |> Map.fetch!(:matrix)
        |> Tuple.to_list()
        |> Enum.map(&Tuple.to_list/1)
        |> trim()

      dark =
        for {row, y} <- Enum.with_index(rows),
            {cell, x} <- Enum.with_index(row),
            cell == 1,
            do: {x, y}

      {:ok, %{size: length(rows), dark: dark}}
    end
  end

  # The library adds a quiet zone; printed codes get their own margin.
  defp trim(rows) do
    rows
    |> drop_blank_rows()
    |> transpose()
    |> drop_blank_rows()
    |> transpose()
  end

  defp drop_blank_rows(rows) do
    rows
    |> Enum.drop_while(&blank?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&blank?/1)
    |> Enum.reverse()
  end

  defp blank?(row), do: Enum.all?(row, &(&1 != 1))

  defp transpose(rows), do: rows |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
end
