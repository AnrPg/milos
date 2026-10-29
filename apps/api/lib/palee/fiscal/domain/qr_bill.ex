defmodule Palee.Fiscal.Domain.QrBill do
  @moduledoc """
  The Swiss QR-bill (ADR-245), per the Swiss Implementation Guidelines for
  the QR-bill v2.4 (SIX, valid from 14 November 2026):

    * the creditor account is a Swiss or Liechtenstein IBAN; a **QR-IBAN**
      only with a **QR reference** (`QRR`, 27 digits, modulo 10 recursive
      check digit) and only in CHF; a plain IBAN with a **Creditor
      Reference** (`SCOR`, ISO 11649, `RF` + modulo 97-10 check digits);
    * addresses are structured only (address type `S`): name, street,
      building number, postal code, town, country; the ultimate creditor
      stays empty;
    * amount `0.01`–`999999999.99` with two decimals, currency CHF or EUR;
    * the payload is UTF-8 with the Swiss character set (Basic Latin,
      Latin-1 Supplement, Latin Extended-A, Ș ș Ț ț €); anything else is
      replaced by `.`; lines are separated by LF, no separator after the
      last element (`EPD`);
    * printed headings are the fixed texts of Annex C in German, French,
      Italian or English (`headings/1`).

  `for_document/3` decides whether a fiscal document gets a QR-bill: an
  invoice of a Swiss or Liechtenstein seller with bank details, in CHF or
  EUR, not paid at issue (no payment method, or bank transfer).
  """

  alias Palee.Fiscal.Domain.Iban

  @max_amount 99_999_999_999
  @lengths %{name: 70, street: 70, building_number: 16, postal_code: 16, city: 35}
  @message_max 140

  @headings %{
    "de" => %{
      payment_part: "Zahlteil",
      receipt: "Empfangsschein",
      account: "Konto / Zahlbar an",
      reference: "Referenz",
      additional_information: "Zusätzliche Informationen",
      payable_by: "Zahlbar durch",
      payable_by_blank: "Zahlbar durch (Name/Adresse)",
      currency: "Währung",
      amount: "Betrag",
      acceptance_point: "Annahmestelle",
      separate: "Vor der Einzahlung abzutrennen"
    },
    "fr" => %{
      payment_part: "Section paiement",
      receipt: "Récépissé",
      account: "Compte / Payable à",
      reference: "Référence",
      additional_information: "Informations supplémentaires",
      payable_by: "Payable par",
      payable_by_blank: "Payable par (nom/adresse)",
      currency: "Monnaie",
      amount: "Montant",
      acceptance_point: "Point de dépôt",
      separate: "A détacher avant le versement"
    },
    "it" => %{
      payment_part: "Sezione pagamento",
      receipt: "Ricevuta",
      account: "Conto / Pagabile a",
      reference: "Riferimento",
      additional_information: "Informazioni supplementari",
      payable_by: "Pagabile da",
      payable_by_blank: "Pagabile da (nome/indirizzo)",
      currency: "Valuta",
      amount: "Importo",
      acceptance_point: "Punto di accettazione",
      separate: "Da staccare prima del versamento"
    },
    "en" => %{
      payment_part: "Payment part",
      receipt: "Receipt",
      account: "Account / Payable to",
      reference: "Reference",
      additional_information: "Additional information",
      payable_by: "Payable by",
      payable_by_blank: "Payable by (name/address)",
      currency: "Currency",
      amount: "Amount",
      acceptance_point: "Acceptance point",
      separate: "Separate before paying in"
    }
  }

  @doc "The fixed headings in `language` (de, fr, it; anything else English)."
  def headings(language), do: Map.get(@headings, language, @headings["en"])

  @doc """
  `{:ok, bill}` or `{:error, reason}` for

      %{account: iban, creditor: address, debtor: address | nil,
        amount_cents: integer | nil, currency: "CHF" | "EUR",
        reference: {:qrr, digits26} | {:scor, text} | :none,
        message: text | nil}

  where an address is `%{name, street, building_number, postal_code, city,
  country_code}`. The bill has the `payload` to encode and the values to
  print (`account`, `reference`, `creditor_lines`, `debtor_lines`,
  `amount`, `currency`, `message`).
  """
  def build(params) do
    account = Iban.normalize(params[:account])
    currency = params[:currency]
    amount = params[:amount_cents]

    with :ok <- check_account(account),
         :ok <- check_currency(currency),
         :ok <- check_amount(amount),
         {:ok, creditor} <- address(params[:creditor], :creditor_address_incomplete),
         {:ok, debtor} <- optional_address(params[:debtor]),
         {:ok, type, reference} <- reference(params[:reference], account, currency) do
      message = params[:message] |> sanitize() |> truncate(@message_max)

      payload =
        Enum.join(
          ["SPC", "0200", "1", account] ++
            address_lines(creditor) ++
            List.duplicate("", 7) ++
            [amount_text(amount), currency] ++
            address_lines(debtor) ++
            [type, reference || "", message || "", "EPD"],
          "\n"
        )

      {:ok,
       %{
         payload: payload,
         account: Iban.format(account),
         reference_type: type,
         reference: format_reference(type, reference),
         creditor: creditor,
         debtor: debtor,
         creditor_lines: print_lines(creditor),
         debtor_lines: debtor && print_lines(debtor),
         amount: amount && print_amount(amount),
         currency: currency,
         message: message
       }}
    end
  end

  @doc """
  The QR-bill of a fiscal document, or nil when it has none (see the module
  doc). `identity` is the seller's current identity (for its IBAN and
  QR-IBAN); `message` is the printed note (e.g. "Invoice I-000042").
  """
  def for_document(document, identity, message) do
    seller = document.seller

    with true <- document.kind == "invoice",
         true <- document.payment_method in [nil, "bank_transfer"],
         true <- seller_field(seller, :country_code) in ["CH", "LI"],
         true <- document.currency in ["CHF", "EUR"],
         {account, reference} when is_binary(account) <-
           account_and_reference(document, identity || %{}),
         {:ok, bill} <-
           build(%{
             account: account,
             creditor: %{
               name: seller_field(seller, :legal_name),
               street: seller_field(seller, :street),
               building_number: seller_field(seller, :building_number),
               postal_code: seller_field(seller, :postal_code),
               city: seller_field(seller, :city),
               country_code: seller_field(seller, :country_code)
             },
             debtor: debtor(document.buyer),
             amount_cents: document.gross_cents,
             currency: document.currency,
             reference: reference,
             message: message
           }) do
      bill
    else
      _no_bill -> nil
    end
  end

  # QR-IBAN with a QR reference in CHF; otherwise a plain CH/LI IBAN with a
  # Creditor Reference built from the document number.
  defp account_and_reference(document, identity) do
    qr_iban = identity[:qr_iban]
    iban = identity[:iban]

    cond do
      document.currency == "CHF" and is_binary(qr_iban) ->
        {qr_iban, {:qrr, qrr_base(document)}}

      is_binary(iban) and String.slice(iban, 0, 2) in ["CH", "LI"] ->
        {iban, {:scor, String.replace(document.number, ~r/[^A-Za-z0-9]/, "")}}

      true ->
        nil
    end
  end

  # 26 digits: kind (1 receipt, 2 invoice, 3 credit note), branch (4) and
  # the sequence (21), so every document of a gym has its own reference.
  defp qrr_base(document) do
    kind = %{"receipt" => "1", "invoice" => "2", "credit_note" => "3"}[document.kind] || "9"
    branch = document.series |> String.replace(~r/\D/, "") |> String.pad_leading(4, "0")
    sequence = document.sequence |> Integer.to_string() |> String.pad_leading(21, "0")
    kind <> String.slice(branch, -4, 4) <> sequence
  end

  defp debtor(nil), do: nil

  defp debtor(buyer) do
    address = %{
      name: seller_field(buyer, :name),
      street: seller_field(buyer, :street),
      building_number: seller_field(buyer, :building_number),
      postal_code: seller_field(buyer, :postal_code),
      city: seller_field(buyer, :city),
      country_code: seller_field(buyer, :country_code)
    }

    if Enum.all?([:name, :postal_code, :city, :country_code], &address[&1]), do: address
  end

  # ── References ────────────────────────────────────────────────────────────

  @doc "A 27-digit QR reference: `base` (up to 26 digits) and its check digit."
  def qr_reference(base) do
    digits = String.pad_leading(base, 26, "0")
    digits <> Integer.to_string(mod10_check(digits))
  end

  @doc "True for a 27-digit QR reference with a correct check digit."
  def valid_qr_reference?(reference) do
    Regex.match?(~r/^\d{27}$/, reference) and
      mod10_check(String.slice(reference, 0, 26)) == String.to_integer(String.last(reference))
  end

  @mod10 {0, 9, 4, 6, 8, 2, 7, 1, 3, 5}

  @doc "Modulo 10 recursive check digit (SIX)."
  def mod10_check(digits) do
    carry =
      digits
      |> String.to_charlist()
      |> Enum.reduce(0, fn char, carry -> elem(@mod10, rem(carry + char - ?0, 10)) end)

    rem(10 - carry, 10)
  end

  @doc "An ISO 11649 Creditor Reference for `text` (1–21 letters and digits)."
  def creditor_reference(text) do
    body = String.upcase(text)
    # mod97/1 moves the first four characters to the end: body <> "RF00".
    "RF" <> two_digits(98 - Iban.mod97("RF00" <> body)) <> body
  end

  @doc "True for a well-formed Creditor Reference with correct check digits."
  def valid_creditor_reference?(reference) do
    Regex.match?(~r/^RF\d{2}[A-Z0-9]{1,21}$/, reference) and Iban.mod97(reference) == 1
  end

  defp two_digits(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp reference({:qrr, base}, account, "CHF") do
    if Iban.qr_iban?(account) and Regex.match?(~r/^\d{1,26}$/, base),
      do: {:ok, "QRR", qr_reference(base)},
      else: {:error, :qr_reference_needs_qr_iban}
  end

  defp reference({:qrr, _base}, _account, _currency), do: {:error, :qr_reference_only_in_chf}

  defp reference({:scor, text}, account, _currency) do
    cond do
      Iban.qr_iban?(account) -> {:error, :qr_iban_needs_qr_reference}
      Regex.match?(~r/^[A-Za-z0-9]{1,21}$/, text) -> {:ok, "SCOR", creditor_reference(text)}
      true -> {:error, :invalid_creditor_reference}
    end
  end

  defp reference(:none, account, _currency) do
    if Iban.qr_iban?(account),
      do: {:error, :qr_iban_needs_qr_reference},
      else: {:ok, "NON", nil}
  end

  defp reference(_reference, _account, _currency), do: {:error, :invalid_reference}

  defp format_reference("QRR", reference) do
    String.slice(reference, 0, 2) <>
      " " <>
      (reference
       |> String.slice(2, 25)
       |> String.graphemes()
       |> Enum.chunk_every(5)
       |> Enum.map_join(" ", &Enum.join/1))
  end

  defp format_reference("SCOR", reference), do: Iban.format(reference)
  defp format_reference(_type, _reference), do: nil

  # ── Checks ────────────────────────────────────────────────────────────────

  defp check_account(account) do
    cond do
      not Iban.valid?(account) -> {:error, :invalid_iban}
      String.slice(account, 0, 2) not in ["CH", "LI"] -> {:error, :iban_not_swiss}
      true -> :ok
    end
  end

  defp check_currency(currency) when currency in ["CHF", "EUR"], do: :ok
  defp check_currency(_currency), do: {:error, :qr_bill_currency}

  defp check_amount(nil), do: :ok
  defp check_amount(cents) when is_integer(cents) and cents >= 1 and cents <= @max_amount, do: :ok
  defp check_amount(_cents), do: {:error, :qr_bill_amount}

  defp optional_address(nil), do: {:ok, nil}
  defp optional_address(address), do: address(address, :debtor_address_incomplete)

  defp address(address, error) when is_map(address) do
    clean =
      Map.new(@lengths, fn {field, max} ->
        {field, address |> Map.get(field) |> sanitize() |> truncate(max)}
      end)
      |> Map.put(:country_code, address |> Map.get(:country_code) |> upcase())

    if Enum.all?([:name, :postal_code, :city], &clean[&1]) and
         is_binary(clean.country_code) and Regex.match?(~r/^[A-Z]{2}$/, clean.country_code),
       do: {:ok, clean},
       else: {:error, error}
  end

  defp address(_address, error), do: {:error, error}

  defp address_lines(nil), do: List.duplicate("", 7)

  defp address_lines(address) do
    [
      "S",
      address.name,
      address.street || "",
      address.building_number || "",
      address.postal_code,
      address.city,
      address.country_code
    ]
  end

  defp print_lines(address) do
    street = [address.street, address.building_number] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
    place = Enum.join([address.postal_code, address.city], " ")
    place = if address.country_code in ["CH"], do: place, else: "#{address.country_code}-#{place}"
    [address.name, street, place] |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp amount_text(nil), do: ""

  defp amount_text(cents),
    do: "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  @doc "An amount as printed on a QR-bill: `1 590.00`."
  def print_amount(cents) do
    units =
      cents
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(" ", &Enum.join/1)
      |> String.reverse()

    "#{units}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  # ── Text ──────────────────────────────────────────────────────────────────

  @doc "Keeps the Swiss QR character set; other characters become `.`."
  def sanitize(nil), do: nil

  def sanitize(value) when is_binary(value) do
    value
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.to_charlist()
    |> Enum.map(fn char -> if allowed?(char), do: char, else: ?. end)
    |> List.to_string()
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  def sanitize(value), do: value |> to_string() |> sanitize()

  defp allowed?(char),
    do:
      char in 0x20..0x7E or char in 0xA0..0xFF or char in 0x100..0x17F or
        char in 0x218..0x21B or char == 0x20AC

  defp truncate(nil, _max), do: nil
  defp truncate(text, max), do: String.slice(text, 0, max)

  defp upcase(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase(_value), do: nil

  defp seller_field(nil, _key), do: nil

  defp seller_field(map, key) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key))) do
      "" -> nil
      value -> value
    end
  end
end
