defmodule Palee.Imports.Domain.Encoding do
  @moduledoc """
  ADR-254: the text encoding of an uploaded file, and its UTF-8 text. Pure.

  Detection order:

    1. a byte order mark: UTF-8 (`EF BB BF`), UTF-16 LE (`FF FE`), UTF-16 BE
       (`FE FF`);
    2. UTF-16 without a mark: most odd (LE) or even (BE) bytes are zero;
    3. valid UTF-8;
    4. a single-byte code page. Greek text in ISO-8859-7 and Windows-1253
       is mostly bytes `C1`–`FE` in runs (whole words); Western text in
       Windows-1252 has them alone among ASCII letters. Between the two
       Greek pages: bytes `80`–`9F` (punctuation in Windows-1253, control
       codes in ISO-8859-7) or `A2` (Ά in Windows-1253) mean Windows-1253;
       `B6` (Ά in ISO-8859-7) without them means ISO-8859-7.

  Excel on Windows saves "CSV" in the system code page (Windows-1252 in
  Western Europe and the US, Windows-1253 in Greece), and "CSV UTF-8" with a
  mark; Google Sheets and Numbers save UTF-8 without one.
  """

  @encodings ~w(utf8 utf16le utf16be windows1252 iso88597 windows1253)

  @doc "Every encoding the detector can answer."
  def encodings, do: @encodings

  @doc """
  `{:ok, utf8_text, encoding, warnings}`; `warnings` holds
  `:undecodable_bytes` when some byte has no character in the chosen page
  (it becomes U+FFFD).
  """
  def to_utf8(binary) when is_binary(binary) do
    encoding = detect(binary)
    {text, warnings} = decode(strip_bom(binary, encoding), encoding)
    {:ok, text, encoding, warnings}
  end

  @doc "The encoding of `binary` (see the module doc)."
  def detect(<<0xEF, 0xBB, 0xBF, _rest::binary>>), do: "utf8"
  def detect(<<0xFF, 0xFE, _rest::binary>>), do: "utf16le"
  def detect(<<0xFE, 0xFF, _rest::binary>>), do: "utf16be"

  def detect(binary) when is_binary(binary) do
    cond do
      utf16?(binary, :little) -> "utf16le"
      utf16?(binary, :big) -> "utf16be"
      String.valid?(binary) -> "utf8"
      greek?(binary) -> greek_page(binary)
      true -> "windows1252"
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>, "utf8"), do: rest
  defp strip_bom(<<0xFF, 0xFE, rest::binary>>, "utf16le"), do: rest
  defp strip_bom(<<0xFE, 0xFF, rest::binary>>, "utf16be"), do: rest
  defp strip_bom(binary, _encoding), do: binary

  # A file without letters outside ASCII is UTF-8 and Windows-1252 alike.
  defp utf16?(binary, endian) do
    sample = binary_part(binary, 0, min(byte_size(binary), 4_000))
    pairs = for <<a, b <- sample>>, do: {a, b}

    zeros =
      Enum.count(pairs, fn {a, b} -> if endian == :little, do: b == 0, else: a == 0 end)

    length(pairs) >= 2 and zeros * 10 >= length(pairs) * 7
  end

  # Greek words are runs of three or more high bytes; Western accents
  # ("é", "ö", even "öß") are not.
  defp greek?(binary) do
    {in_runs, total} =
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_by(&(&1 >= 0xC1 and &1 <= 0xFE))
      |> Enum.filter(fn [byte | _] -> byte >= 0xC1 and byte <= 0xFE end)
      |> Enum.reduce({0, 0}, fn chunk, {in_runs, total} ->
        size = length(chunk)
        {if(size >= 3, do: in_runs + size, else: in_runs), total + size}
      end)

    in_runs > 0 and in_runs * 2 >= total
  end

  defp greek_page(binary) do
    bytes = :binary.bin_to_list(binary)
    windows_only = Enum.any?(bytes, &(&1 in 0x80..0x9F or &1 == 0xA2))

    cond do
      windows_only -> "windows1253"
      Enum.member?(bytes, 0xB6) -> "iso88597"
      true -> "windows1253"
    end
  end

  # ── Decoding ────────────────────────────────────────────────────────────

  defp decode(binary, "utf8") do
    if String.valid?(binary),
      do: {binary, []},
      else: {String.replace_invalid(binary, "�"), [:undecodable_bytes]}
  end

  defp decode(binary, "utf16le"), do: utf16(binary, :little)
  defp decode(binary, "utf16be"), do: utf16(binary, :big)

  defp decode(binary, page) do
    table = table(page)

    {chars, bad} =
      for <<byte <- binary>>, reduce: {[], false} do
        {acc, bad} ->
          case char(byte, table) do
            nil -> {[0xFFFD | acc], true}
            code -> {[code | acc], bad}
          end
      end

    text = chars |> Enum.reverse() |> List.to_string()
    {text, if(bad, do: [:undecodable_bytes], else: [])}
  end

  defp utf16(binary, endian) do
    even = binary_part(binary, 0, byte_size(binary) - rem(byte_size(binary), 2))

    case :unicode.characters_to_binary(even, {:utf16, endian}, :utf8) do
      text when is_binary(text) ->
        {text, if(even == binary, do: [], else: [:undecodable_bytes])}

      {_error, good, _rest} ->
        {good <> "�", [:undecodable_bytes]}

      _other ->
        {"", [:undecodable_bytes]}
    end
  end

  defp char(byte, _table) when byte < 0x80, do: byte
  defp char(byte, table), do: Map.get(table, byte, :identity) |> identity(byte)

  defp identity(:identity, byte), do: byte
  defp identity(code, _byte), do: code

  # Bytes 80–FF that differ from Latin-1 (`nil` = no character).
  @cp1252 %{
    0x80 => 0x20AC,
    0x81 => nil,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8D => nil,
    0x8E => 0x017D,
    0x8F => nil,
    0x90 => nil,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9D => nil,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  # Greek letters C0–FE (except D2) are U+0390 + (byte − C0) in both pages.
  @greek_letters for(byte <- 0xC0..0xFE, byte != 0xD2, into: %{}, do: {byte, 0x0390 + byte - 0xC0})
                 |> Map.merge(%{0xD2 => nil, 0xFF => nil})

  @iso88597 Map.merge(@greek_letters, %{
              0xA1 => 0x2018,
              0xA2 => 0x2019,
              0xA4 => 0x20AC,
              0xA5 => 0x20AF,
              0xAA => 0x037A,
              0xAE => nil,
              0xAF => 0x2015,
              0xB4 => 0x0384,
              0xB5 => 0x0385,
              0xB6 => 0x0386,
              0xB8 => 0x0388,
              0xB9 => 0x0389,
              0xBA => 0x038A,
              0xBC => 0x038C,
              0xBE => 0x038E,
              0xBF => 0x038F
            })

  @cp1253 @cp1252
          |> Map.merge(%{
            0x88 => nil,
            0x8A => nil,
            0x8C => nil,
            0x8E => nil,
            0x98 => nil,
            0x9A => nil,
            0x9C => nil,
            0x9E => nil,
            0x9F => nil
          })
          |> Map.merge(@greek_letters)
          |> Map.merge(%{
            0xA1 => 0x0385,
            0xA2 => 0x0386,
            0xAA => nil,
            0xAF => 0x2015,
            0xB4 => 0x0384,
            0xB8 => 0x0388,
            0xB9 => 0x0389,
            0xBA => 0x038A,
            0xBC => 0x038C,
            0xBE => 0x038E,
            0xBF => 0x038F
          })

  defp table("windows1252"), do: @cp1252
  defp table("iso88597"), do: @iso88597
  defp table("windows1253"), do: @cp1253
end
