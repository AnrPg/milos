defmodule Palee.Imports.Domain.CsvParser do
  @moduledoc """
  ADR-254: CSV text (already UTF-8) to rows of cells. Pure.

    * delimiter `,`, `;` or tab, detected from the first lines (the one that
      splits them into the same number of cells, more than one); an Excel
      `sep=;` first line names it;
    * RFC 4180 quoting: fields in double quotes may hold delimiters, line
      breaks and `""` for a quote;
    * line breaks `\\r\\n`, `\\n` or `\\r`;
    * cells are trimmed; empty lines are dropped.
  """

  @delimiters [",", ";", "\t"]
  @sample_lines 20

  def delimiters, do: @delimiters

  @doc """
  `{:ok, %{delimiter, header, rows}}` (the first non-empty row is the
  header) or `{:error, :empty_file | :unbalanced_quotes}`.
  """
  def parse(text, opts \\ []) when is_binary(text) do
    {text, hinted} = sep_hint(text)
    delimiter = opts[:delimiter] || hinted || detect_delimiter(text)

    case rows(text, delimiter) do
      {:ok, []} ->
        {:error, :empty_file}

      {:ok, [header | rows]} ->
        width = length(header)
        rows = Enum.map(rows, &pad(&1, width))
        {:ok, %{delimiter: delimiter, header: header, rows: rows}}

      error ->
        error
    end
  end

  defp sep_hint(text) do
    case Regex.run(~r/\A"?sep=(.)"?\r?\n/, text) do
      [line, sep] when sep in @delimiters ->
        {binary_part(text, byte_size(line), byte_size(text) - byte_size(line)), sep}

      _none ->
        {text, nil}
    end
  end

  @doc "The delimiter that splits the first lines most consistently."
  def detect_delimiter(text) do
    lines =
      text
      |> String.split(["\r\n", "\n", "\r"])
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.take(@sample_lines)

    @delimiters
    |> Enum.map(fn delimiter ->
      counts = Enum.map(lines, &count_outside_quotes(&1, delimiter))
      first = List.first(counts) || 0
      consistent = Enum.count(counts, &(&1 == first))
      {delimiter, first, consistent}
    end)
    |> Enum.filter(fn {_delimiter, first, _consistent} -> first > 0 end)
    |> Enum.max_by(fn {_d, first, consistent} -> {consistent, first} end, fn -> {",", 0, 0} end)
    |> elem(0)
  end

  defp count_outside_quotes(line, delimiter) do
    line
    |> String.graphemes()
    |> Enum.reduce({0, false}, fn
      "\"", {count, quoted} -> {count, not quoted}
      ^delimiter, {count, false} -> {count + 1, false}
      _char, acc -> acc
    end)
    |> elem(0)
  end

  # A small state machine over the bytes; the delimiter and quotes are ASCII,
  # so UTF-8 sequences pass through untouched.
  defp rows(text, delimiter) do
    <<sep>> = delimiter
    do_rows(text, sep, [], [], [], :start)
  end

  # state: :start (cell start), :plain, :quoted, :quote (a quote inside quotes)
  defp do_rows(<<>>, _sep, cell, row, rows, state) do
    if state == :quoted do
      {:error, :unbalanced_quotes}
    else
      {:ok, finish_row(cell, row, rows) |> Enum.reverse() |> Enum.reject(&blank_row?/1)}
    end
  end

  defp do_rows(<<?", rest::binary>>, sep, cell, row, rows, :start),
    do: do_rows(rest, sep, cell, row, rows, :quoted)

  defp do_rows(<<?", ?", rest::binary>>, sep, cell, row, rows, :quoted),
    do: do_rows(rest, sep, [?" | cell], row, rows, :quoted)

  defp do_rows(<<?", rest::binary>>, sep, cell, row, rows, :quoted),
    do: do_rows(rest, sep, cell, row, rows, :quote)

  defp do_rows(<<char, rest::binary>>, sep, cell, row, rows, :quoted),
    do: do_rows(rest, sep, [char | cell], row, rows, :quoted)

  defp do_rows(<<char, rest::binary>>, sep, cell, row, rows, _state) when char == sep,
    do: do_rows(rest, sep, [], [cell_value(cell) | row], rows, :start)

  defp do_rows(<<?\r, ?\n, rest::binary>>, sep, cell, row, rows, _state),
    do: do_rows(rest, sep, [], [], finish_row(cell, row, rows), :start)

  defp do_rows(<<char, rest::binary>>, sep, cell, row, rows, _state) when char in [?\n, ?\r],
    do: do_rows(rest, sep, [], [], finish_row(cell, row, rows), :start)

  # Text after a closing quote ("ab"c) is kept, as spreadsheets do.
  defp do_rows(<<char, rest::binary>>, sep, cell, row, rows, _state),
    do: do_rows(rest, sep, [char | cell], row, rows, :plain)

  defp finish_row(cell, row, rows), do: [Enum.reverse([cell_value(cell) | row]) | rows]

  defp cell_value(chars), do: chars |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

  defp blank_row?(row), do: Enum.all?(row, &(&1 == ""))

  defp pad(row, width) when length(row) >= width, do: row
  defp pad(row, width), do: row ++ List.duplicate("", width - length(row))
end
