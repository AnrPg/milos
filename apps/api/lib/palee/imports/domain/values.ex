defmodule Palee.Imports.Domain.Values do
  @moduledoc """
  ADR-254: one cell to one value. Pure. Every reader answers `{:ok, value}`,
  `:blank` or `{:error, code}`.

    * **email**: trimmed and lower-cased; one `@`, a dot in the domain;
    * **phone**: the digits (a leading `+` or `00` kept as the country
      code); people are matched on the **last 10 digits**, so
      `+30 694 123 4567`, `0030 6941234567` and `6941234567` are the same
      person, and so are US numbers with or without `+1`;
    * **money**: integer cents. `1.234,56` and `1,234.56` are both
      1234.56: the last separator followed by one or two digits is the
      decimal mark; a lone separator followed by three digits groups
      thousands (`1.500` = 1500); currency signs, codes and spaces are
      ignored; `(12.00)` and `-12` are negative;
    * **text**: trimmed, inner whitespace collapsed, at most 500 characters.
  """

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @max_text 500
  @phone_key_digits 10
  @min_phone_digits 7

  def phone_key_digits, do: @phone_key_digits

  def email(value) do
    case text(value) do
      {:ok, text} ->
        email = String.downcase(text)
        if Regex.match?(@email, email), do: {:ok, email}, else: {:error, :invalid_email}

      other ->
        other
    end
  end

  def phone(value) do
    case text(value) do
      {:ok, text} ->
        international = Regex.match?(~r/^\s*(\+|00)/, text)
        digits = String.replace(text, ~r/\D/, "")
        digits = if String.starts_with?(text, "00"), do: String.slice(digits, 2..-1//1), else: digits

        cond do
          String.length(digits) < @min_phone_digits or String.length(digits) > 15 ->
            {:error, :invalid_phone}

          international ->
            {:ok, "+" <> digits}

          true ->
            {:ok, digits}
        end

      other ->
        other
    end
  end

  @doc "The matching key of a phone: its last 10 digits (nil for nil)."
  def phone_key(nil), do: nil

  def phone_key(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/\D/, "")
    String.slice(digits, max(String.length(digits) - @phone_key_digits, 0)..-1//1)
  end

  def money(value) do
    case text(value) do
      {:ok, text} -> parse_money(text)
      other -> other
    end
  end

  defp parse_money(text) do
    negative = Regex.match?(~r/^\(.*\)$|^-|-$|^[^\d]*-/, text)
    cleaned = String.replace(text, ~r/[^\d.,]/u, "")

    with true <- cleaned != "" || {:error, :invalid_amount},
         {:ok, cents} <- cents(cleaned) do
      {:ok, if(negative, do: -cents, else: cents)}
    else
      {:error, _code} = error -> error
      _other -> {:error, :invalid_amount}
    end
  end

  defp cents(number) do
    case Regex.run(~r/^(.*?)([.,])(\d+)$/, number) do
      [_all, integer, _mark, fraction] when byte_size(fraction) in [1, 2] ->
        whole(integer, String.pad_trailing(fraction, 2, "0"))

      [_all, integer, mark, fraction] when byte_size(fraction) == 3 ->
        # "1.500" / "1,500" group thousands unless the other mark is the
        # decimal one already ("1,500.5" never gets here).
        if String.contains?(integer, if(mark == ".", do: ",", else: ".")),
          do: {:error, :invalid_amount},
          else: whole(integer <> fraction, "00")

      [_all, _integer, _mark, _fraction] ->
        {:error, :invalid_amount}

      nil ->
        whole(number, "00")
    end
  end

  defp whole(integer, fraction) do
    digits = String.replace(integer, ~r/[.,]/, "")

    with true <- Regex.match?(~r/^\d*$/, digits),
         {units, ""} <- Integer.parse(if(digits == "", do: "0", else: digits)),
         {cents, ""} <- Integer.parse(fraction) do
      {:ok, units * 100 + cents}
    else
      _other -> {:error, :invalid_amount}
    end
  end

  def text(nil), do: :blank

  def text(value) when is_binary(value) do
    case value |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> :blank
      text -> {:ok, String.slice(text, 0, @max_text)}
    end
  end

  def text(_value), do: {:error, :invalid_text}

  @doc "A client role: member (default words) or athlete."
  def role(value) do
    case text(value) do
      {:ok, text} ->
        folded = fold(text)

        cond do
          folded in folded(~w(athlete athletes αθλητής αθλήτρια αθλητές)) -> {:ok, "athlete"}
          folded in folded(~w(member members client customer μέλος μέλη πελάτης)) -> {:ok, "member"}
          true -> {:error, :invalid_role}
        end

      other ->
        other
    end
  end

  @payment_methods %{
    "cash" => ~w(cash μετρητα),
    "card_manual" =>
      ~w(card credit debit visa mastercard amex pos καρτα πιστωτικη χρεωστικη stripe square),
    "bank_transfer" => ~w(bank transfer wire iban sepa ach τραπεζα καταθεση εμβασμα μεταφορα),
    "other" => ~w(other cheque check paypal αλλο επιταγη)
  }

  @doc "A payment method of Finance; unknown words are `other`."
  def payment_method(value) do
    case text(value) do
      {:ok, text} ->
        words = text |> fold() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

        method =
          Enum.find_value(@payment_methods, "other", fn {method, keys} ->
            if Enum.any?(words, &(&1 in folded(keys))), do: method
          end)

        {:ok, method}

      other ->
        other
    end
  end

  @statuses %{
    "active" => ~w(active current ok paid ενεργο ενεργη ενεργος),
    "expired" => ~w(expired inactive lapsed ended ληγμενο ληγμενη ανενεργο ανενεργη εληξε),
    "cancelled" => ~w(cancelled canceled terminated ακυρωμενο ακυρωμενη διακοπη),
    "paused" => ~w(paused frozen hold suspended παγωμενο παγωμενη παυση αναστολη),
    "trial" => ~w(trial lead prospect δοκιμαστικο δοκιμη)
  }

  @doc "A Finance profile status from a status word of another system."
  def membership_status(value) do
    case text(value) do
      {:ok, text} ->
        words = text |> fold() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

        case Enum.find(@statuses, fn {_status, keys} ->
               Enum.any?(words, &(&1 in folded(keys)))
             end) do
          {status, _keys} -> {:ok, status}
          nil -> {:error, :invalid_status}
        end

      other ->
        other
    end
  end

  defp folded(words), do: Enum.map(words, &fold/1)

  @doc "Lower case without accents, for comparing words."
  def fold(text) do
    text
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("ς", "σ")
    |> String.normalize(:nfc)
  end
end
