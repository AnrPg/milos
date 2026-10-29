defmodule Palee.Fiscal.Domain.TaxId do
  @moduledoc """
  Format and check-digit validation of tax identifiers (ADR-240).

  Three kinds per country:

    * `:tax_id` – the national tax number (ΑΦΜ, TIC, Steuernummer, enterprise
      number, UTR, EIN, …);
    * `:vat_number` – the VAT number with its country prefix (`EL`, `CHE`,
      `ATU`, …), stored without spaces, dots or dashes;
    * `:registration_number` – the trade register number where one is printed
      (SIREN/SIRET, ΓΕΜΗ, …).

  Check digits are verified where the algorithm is published: Greek ΑΦΜ,
  German and Austrian VAT numbers, Swiss UID, Belgian enterprise number,
  Luxembourg VAT number, French SIREN/SIRET (Luhn) and the French VAT key.
  Elsewhere only the shape is checked. Whether a VAT number is live (VIES,
  HMRC) is a separate, later check.
  """

  @doc "Strips spaces, dots, dashes and slashes and upper-cases the value."
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value
    |> String.upcase()
    |> String.replace(~r/[\s.\-\/]/u, "")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  @doc """
  `{:ok, normalized}` or `{:error, reason}` for a value of `kind` in
  `country`. Accepts a VAT number with or without its prefix and returns it
  with the prefix.
  """
  def validate(country, kind, value) do
    case normalize(value) do
      nil -> {:error, :blank}
      normalized -> check(country, kind, normalized)
    end
  end

  # ── Greece ────────────────────────────────────────────────────────────────
  defp check("GR", :tax_id, value), do: afm(value)

  defp check("GR", :vat_number, value) do
    with {:ok, afm} <- value |> strip_prefix(["EL", "GR"]) |> afm(), do: {:ok, "EL" <> afm}
  end

  defp check("GR", :registration_number, value), do: digits(value, 9..12)

  # ── Cyprus ────────────────────────────────────────────────────────────────
  defp check("CY", :tax_id, value), do: pattern(value, ~r/^\d{8}[A-Z]$/)

  defp check("CY", :vat_number, value),
    do: prefixed(value, "CY", &pattern(&1, ~r/^\d{8}[A-Z]$/))

  defp check("CY", :registration_number, value), do: pattern(value, ~r/^[A-Z]{0,2}\d{1,8}$/)

  # ── Germany ───────────────────────────────────────────────────────────────
  defp check("DE", :tax_id, value), do: digits(value, 10..13)
  defp check("DE", :vat_number, value), do: prefixed(value, "DE", &de_vat/1)

  defp check("DE", :registration_number, value),
    do: pattern(value, ~r/^(HRA|HRB|GNR|PR|VR)?\d{1,7}[A-Z]?$/)

  # ── Austria ───────────────────────────────────────────────────────────────
  defp check("AT", :tax_id, value), do: digits(value, 9..9)
  defp check("AT", :vat_number, value), do: prefixed(value, "ATU", &at_vat/1, ["AT"])
  defp check("AT", :registration_number, value), do: pattern(value, ~r/^(FN)?\d{1,6}[A-Z]$/)

  # ── Switzerland and Liechtenstein ────────────────────────────────────────
  defp check("CH", kind, value) when kind in [:tax_id, :vat_number, :registration_number],
    do: swiss_uid(value, kind)

  defp check("LI", :vat_number, value), do: prefixed(value, "LI", &digits(&1, 5..5), ["FL"])
  defp check("LI", :tax_id, value), do: digits(value, 5..12)
  defp check("LI", :registration_number, value), do: pattern(value, ~r/^(FL)?\d{10,11}$/)

  # ── Luxembourg ────────────────────────────────────────────────────────────
  defp check("LU", :tax_id, value), do: digits(value, 11..13)
  defp check("LU", :vat_number, value), do: prefixed(value, "LU", &lu_vat/1)
  defp check("LU", :registration_number, value), do: pattern(value, ~r/^[A-Z]\d{1,6}$/)

  # ── France and Monaco ─────────────────────────────────────────────────────
  defp check(country, :registration_number, value) when country in ["FR"],
    do: siren_or_siret(value)

  defp check("MC", :registration_number, value), do: pattern(value, ~r/^\d{2}[A-Z]\d{5}$/)

  defp check(country, :tax_id, value) when country in ["FR", "MC"], do: digits(value, 13..13)

  defp check(country, :vat_number, value) when country in ["FR", "MC"],
    do: prefixed(value, "FR", &fr_vat/1)

  # ── Belgium ───────────────────────────────────────────────────────────────
  defp check("BE", kind, value) when kind in [:tax_id, :registration_number],
    do: be_enterprise(value)

  defp check("BE", :vat_number, value), do: prefixed(value, "BE", &be_enterprise/1)

  # ── United Kingdom ────────────────────────────────────────────────────────
  defp check("GB", :tax_id, value), do: digits(value, 10..10)

  defp check("GB", :vat_number, value),
    do: prefixed(value, "GB", &pattern(&1, ~r/^(\d{9}|\d{12}|GD\d{3}|HA\d{3})$/))

  defp check("GB", :registration_number, value), do: pattern(value, ~r/^([A-Z]{2}\d{6}|\d{8})$/)

  # ── United States ─────────────────────────────────────────────────────────
  defp check("US", :tax_id, value), do: digits(value, 9..9)
  defp check("US", :vat_number, _value), do: {:error, :not_applicable}
  defp check("US", :registration_number, value), do: pattern(value, ~r/^[A-Z0-9]{1,20}$/)

  defp check(_country, _kind, _value), do: {:error, :unsupported_country}

  # ── Algorithms ────────────────────────────────────────────────────────────

  # ΑΦΜ: Σ d_i·2^(9-i) for the first eight digits, mod 11, mod 10 = ninth.
  defp afm(value) do
    with {:ok, value} <- digits(value, 9..9) do
      [check | rest] = value |> to_digits() |> Enum.reverse()

      sum =
        rest
        |> Enum.with_index(1)
        |> Enum.reduce(0, fn {digit, power}, acc -> acc + digit * Integer.pow(2, power) end)

      if value != "000000000" and rem(rem(sum, 11), 10) == check,
        do: {:ok, value},
        else: {:error, :check_digit}
    end
  end

  # ISO 7064 MOD 11,10 over the first eight digits.
  defp de_vat(value) do
    with {:ok, value} <- digits(value, 9..9) do
      {body, [check]} = value |> to_digits() |> Enum.split(8)

      product =
        Enum.reduce(body, 10, fn digit, product ->
          sum = rem(digit + product, 10)
          sum = if sum == 0, do: 10, else: sum
          rem(2 * sum, 11)
        end)

      expected = rem(11 - product, 10)
      if expected == check, do: {:ok, value}, else: {:error, :check_digit}
    end
  end

  # UID: S = c1 + q(2·c2) + c3 + q(2·c4) + c5 + q(2·c6) + c7, check = (6 - S) mod 10.
  defp at_vat(value) do
    with {:ok, value} <- digits(value, 8..8) do
      {body, [check]} = value |> to_digits() |> Enum.split(7)

      sum =
        body
        |> Enum.with_index()
        |> Enum.reduce(0, fn
          {digit, index}, acc when rem(index, 2) == 1 -> acc + cross_sum(2 * digit)
          {digit, _index}, acc -> acc + digit
        end)

      if Integer.mod(6 - sum, 10) == check, do: {:ok, value}, else: {:error, :check_digit}
    end
  end

  # CHE + 9 digits; weights 5 4 3 2 7 6 5 4, check = 11 - sum mod 11 (11 → 0, 10 invalid).
  defp swiss_uid(value, kind) do
    stripped =
      value
      |> String.replace(~r/(MWST|TVA|IVA|HR)$/, "")
      |> strip_prefix(["CHE"])

    with {:ok, number} <- digits(stripped, 9..9) do
      {body, [check]} = number |> to_digits() |> Enum.split(8)

      sum =
        body
        |> Enum.zip([5, 4, 3, 2, 7, 6, 5, 4])
        |> Enum.reduce(0, fn {d, w}, a -> a + d * w end)

      expected =
        case 11 - rem(sum, 11) do
          11 -> 0
          other -> other
        end

      cond do
        expected == 10 or expected != check -> {:error, :check_digit}
        kind == :vat_number -> {:ok, "CHE" <> number <> "MWST"}
        true -> {:ok, "CHE" <> number}
      end
    end
  end

  # First six digits mod 89 = last two.
  defp lu_vat(value) do
    with {:ok, value} <- digits(value, 8..8) do
      {body, check} = String.split_at(value, 6)

      if rem(String.to_integer(body), 89) == String.to_integer(check),
        do: {:ok, value},
        else: {:error, :check_digit}
    end
  end

  defp siren_or_siret(value) do
    with {:ok, value} <- digits(value, 9..14),
         true <- String.length(value) in [9, 14] || {:error, :format} do
      if luhn?(value), do: {:ok, value}, else: {:error, :check_digit}
    end
  end

  # FR + two-character key + SIREN; numeric key = (12 + 3·(SIREN mod 97)) mod 97.
  defp fr_vat(value) do
    with true <- Regex.match?(~r/^[0-9A-Z]{2}\d{9}$/, value) || {:error, :format},
         {key, siren} = String.split_at(value, 2),
         {:ok, _siren} <- siren_or_siret(siren) do
      case Integer.parse(key) do
        {numeric, ""} ->
          if numeric == rem(12 + 3 * rem(String.to_integer(siren), 97), 97),
            do: {:ok, value},
            else: {:error, :check_digit}

        _alphanumeric_key ->
          {:ok, value}
      end
    end
  end

  # Ten digits starting 0 or 1 (nine-digit legacy numbers get a leading 0);
  # last two = 97 - first eight mod 97.
  defp be_enterprise(value) do
    value = if Regex.match?(~r/^\d{9}$/, value), do: "0" <> value, else: value

    with true <- Regex.match?(~r/^[01]\d{9}$/, value) || {:error, :format} do
      {body, check} = String.split_at(value, 8)

      if 97 - rem(String.to_integer(body), 97) == String.to_integer(check),
        do: {:ok, value},
        else: {:error, :check_digit}
    end
  end

  defp luhn?(value) do
    value
    |> to_digits()
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn
      {digit, index}, acc when rem(index, 2) == 1 -> acc + cross_sum(2 * digit)
      {digit, _index}, acc -> acc + digit
    end)
    |> rem(10) == 0
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp prefixed(value, prefix, checker, aliases \\ []) do
    with {:ok, body} <- checker.(strip_prefix(value, [prefix | aliases])) do
      {:ok, prefix <> body}
    end
  end

  defp strip_prefix(value, prefixes) do
    Enum.find_value(prefixes, value, fn prefix ->
      if String.starts_with?(value, prefix), do: String.replace_prefix(value, prefix, "")
    end)
  end

  defp digits(value, range) do
    if Regex.match?(~r/^\d+$/, value) and String.length(value) in range,
      do: {:ok, value},
      else: {:error, :format}
  end

  defp pattern(value, regex),
    do: if(Regex.match?(regex, value), do: {:ok, value}, else: {:error, :format})

  defp to_digits(value), do: value |> String.graphemes() |> Enum.map(&String.to_integer/1)

  defp cross_sum(number) when number < 10, do: number
  defp cross_sum(number), do: div(number, 10) + rem(number, 10)
end
