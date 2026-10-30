defmodule Palee.Fiscal.Domain.ExportCsv do
  @moduledoc """
  CSV writing for the accounting export formats (ADR-245): RFC 4180
  quoting with any separator, CRLF line ends, a guard against spreadsheet
  formulas, amounts from integer cents with either decimal mark, the date
  layouts the formats ask for, and Windows-1252 for DATEV.
  """

  @doc """
  Encodes rows (lists of cells) as CSV. Options: `:separator` (default
  `","`), `:quote_all` (default false), `:guard` (default true: a text
  cell starting with `= + - @`, tab or CR gets a leading `'`).
  Cells may be strings, integers, nil, or `{:raw, text}` (written as is).
  """
  def encode(rows, opts \\ []) do
    separator = Keyword.get(opts, :separator, ",")
    quote_all = Keyword.get(opts, :quote_all, false)
    guard = Keyword.get(opts, :guard, true)

    Enum.map_join(rows, "", fn row ->
      Enum.map_join(row, separator, &cell(&1, separator, quote_all, guard)) <> "\r\n"
    end)
  end

  defp cell(nil, _separator, _quote_all, _guard), do: ""
  defp cell({:raw, text}, _separator, _quote_all, _guard), do: text

  defp cell(value, _separator, _quote_all, _guard) when is_integer(value),
    do: Integer.to_string(value)

  defp cell(value, separator, quote_all, guard) do
    text = value |> to_string() |> then(&if(guard, do: guard_formula(&1), else: &1))

    if quote_all or String.contains?(text, [separator, "\"", "\r", "\n"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end

  @doc "Prefixes a cell that a spreadsheet would read as a formula with `'`."
  def guard_formula(<<first, _rest::binary>> = value) when first in [?=, ?+, ?@, ?\t, ?\r],
    do: "'" <> value

  # A leading minus is a formula trigger too, except in a plain number.
  def guard_formula("-" <> rest = value) do
    if Regex.match?(~r/^\d+([.,]\d+)?$/, rest), do: value, else: "'" <> value
  end

  def guard_formula(value), do: value

  @doc "Cents as a decimal amount: `amount(-123_456, \",\")` is `\"-1234,56\"`."
  def amount(cents, decimal_mark \\ ".") when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    abs = abs(cents)

    sign <>
      Integer.to_string(div(abs, 100)) <>
      decimal_mark <> String.pad_leading(Integer.to_string(rem(abs, 100)), 2, "0")
  end

  @doc "A rate in basis points as a decimal percentage (`1900` → `\"19.00\"`)."
  def rate(rate_bp, decimal_mark \\ "."), do: amount(rate_bp || 0, decimal_mark)

  @doc """
  Formats a date: `:iso` (2027-02-03), `:dmy` (03/02/2027), `:mdy`
  (02/03/2027), `:dmy_dot` (03.02.2027), `:ddmm` (0302, DATEV Belegdatum),
  `:yyyymmdd` (20270203).
  """
  def date(nil, _layout), do: nil
  def date(%Date{} = date, :iso), do: Date.to_iso8601(date)
  def date(%Date{} = date, :dmy), do: "#{pad(date.day)}/#{pad(date.month)}/#{date.year}"
  def date(%Date{} = date, :mdy), do: "#{pad(date.month)}/#{pad(date.day)}/#{date.year}"
  def date(%Date{} = date, :dmy_dot), do: "#{pad(date.day)}.#{pad(date.month)}.#{date.year}"
  def date(%Date{} = date, :ddmm), do: pad(date.day) <> pad(date.month)
  def date(%Date{} = date, :yyyymmdd), do: "#{date.year}#{pad(date.month)}#{pad(date.day)}"

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc "Cuts text to `max` characters (nil stays nil)."
  def truncate(nil, _max), do: nil
  def truncate(text, max), do: text |> to_string() |> String.slice(0, max)

  # Windows-1252 bytes 0x80–0x9F that differ from Latin-1.
  @cp1252 %{
    0x20AC => 0x80,
    0x201A => 0x82,
    0x0192 => 0x83,
    0x201E => 0x84,
    0x2026 => 0x85,
    0x2020 => 0x86,
    0x2021 => 0x87,
    0x02C6 => 0x88,
    0x2030 => 0x89,
    0x0160 => 0x8A,
    0x2039 => 0x8B,
    0x0152 => 0x8C,
    0x017D => 0x8E,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x02DC => 0x98,
    0x2122 => 0x99,
    0x0161 => 0x9A,
    0x203A => 0x9B,
    0x0153 => 0x9C,
    0x017E => 0x9E,
    0x0178 => 0x9F
  }

  @doc """
  UTF-8 text as Windows-1252 bytes. Characters Windows-1252 cannot hold
  are first decomposed (é stays é, ő becomes o) and otherwise become `?`
  (Greek text, for instance).
  """
  def to_cp1252(text) when is_binary(text) do
    for <<codepoint::utf8 <- text>>, into: <<>>, do: cp1252_char(codepoint)
  end

  defp cp1252_char(codepoint) when codepoint < 0x80, do: <<codepoint>>
  defp cp1252_char(codepoint) when codepoint in 0xA0..0xFF, do: <<codepoint>>

  defp cp1252_char(codepoint) do
    case Map.fetch(@cp1252, codepoint) do
      {:ok, byte} ->
        <<byte>>

      :error ->
        case :unicode.characters_to_nfd_binary(<<codepoint::utf8>>) do
          <<base::utf8, _marks::binary>> when base != codepoint and base < 0x80 -> <<base>>
          _ -> "?"
        end
    end
  end
end
