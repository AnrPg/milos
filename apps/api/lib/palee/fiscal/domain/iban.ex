defmodule Palee.Fiscal.Domain.Iban do
  @moduledoc """
  International Bank Account Numbers (ISO 13616) for the bank details on
  invoices and the Swiss QR-bill (ADR-245).

  An IBAN is valid when it has the country's length, its characters are
  letters and digits, and moving the first four characters to the end and
  turning letters into numbers (A = 10 … Z = 35) leaves a remainder of 1
  modulo 97.

  A **QR-IBAN** is a Swiss or Liechtenstein IBAN whose institution id
  (characters 5–9) is between 30000 and 31999. It may only be used with a
  QR reference (QRR) on a QR-bill, and a plain IBAN never with one
  (SIX IG QR-bill v2.4, §4.3.2).
  """

  # ISO 13616 registry lengths of the countries Palee serves and their
  # neighbours; other countries are checked with the generic 15–34 bound.
  @lengths %{
    "AD" => 24,
    "AT" => 20,
    "BE" => 16,
    "BG" => 22,
    "CH" => 21,
    "CY" => 28,
    "CZ" => 24,
    "DE" => 22,
    "DK" => 18,
    "EE" => 20,
    "ES" => 24,
    "FI" => 18,
    "FR" => 27,
    "GB" => 22,
    "GR" => 27,
    "HR" => 21,
    "HU" => 28,
    "IE" => 22,
    "IT" => 27,
    "LI" => 21,
    "LT" => 20,
    "LU" => 20,
    "LV" => 21,
    "MC" => 27,
    "MT" => 31,
    "NL" => 18,
    "NO" => 15,
    "PL" => 28,
    "PT" => 25,
    "RO" => 24,
    "SE" => 24,
    "SI" => 19,
    "SK" => 24,
    "SM" => 27
  }

  @doc "Removes spaces and upper-cases; nil for blank input."
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    case value |> String.replace(~r/[\s\-]/u, "") |> String.upcase() do
      "" -> nil
      iban -> iban
    end
  end

  def normalize(_value), do: nil

  @doc "`{:ok, normalized}` or `{:error, :invalid_iban}`."
  def validate(value) do
    iban = normalize(value)

    if is_binary(iban) and valid?(iban), do: {:ok, iban}, else: {:error, :invalid_iban}
  end

  @doc "True for a well-formed IBAN with a correct check (mod 97 = 1)."
  def valid?(iban) when is_binary(iban) do
    Regex.match?(~r/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/, iban) and length_ok?(iban) and
      mod97(iban) == 1
  end

  def valid?(_iban), do: false

  @doc "True for a Swiss or Liechtenstein QR-IBAN (institution id 30000–31999)."
  def qr_iban?(iban) when is_binary(iban) do
    with true <- String.slice(iban, 0, 2) in ["CH", "LI"],
         {iid, ""} <- Integer.parse(String.slice(iban, 4, 5)) do
      iid in 30_000..31_999
    else
      _ -> false
    end
  end

  def qr_iban?(_iban), do: false

  @doc "Groups of four characters, as printed (`CH44 3199 9123 0008 8901 2`)."
  def format(nil), do: nil

  def format(iban) when is_binary(iban) do
    iban
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc "ISO 7064 MOD 97-10 remainder of the rearranged IBAN."
  def mod97(iban) do
    <<head::binary-size(4), rest::binary>> = iban

    (rest <> head)
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      char, acc when char in ?0..?9 -> rem(acc * 10 + (char - ?0), 97)
      char, acc when char in ?A..?Z -> rem(acc * 100 + (char - ?A + 10), 97)
    end)
  end

  defp length_ok?(iban) do
    case Map.get(@lengths, String.slice(iban, 0, 2)) do
      nil -> byte_size(iban) in 15..34
      expected -> byte_size(iban) == expected
    end
  end
end
