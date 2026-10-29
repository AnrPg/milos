defmodule Palee.Fiscal.Domain.DocumentView do
  @moduledoc """
  What a fiscal document shows, per country and language (ADR-245). Pure:
  the HTML and PDF renderers draw this map and decide nothing.

  Built from the immutable document (with its lines), the translated labels
  (`DocumentLabels`) and, when present, the document it corrects, its
  report to the tax authority and the seller's current bank details:

    * title: the document kind; in Greece the myDATA type name
      (Απόδειξη Παροχής Υπηρεσιών 11.2, Τιμολόγιο Παροχής Υπηρεσιών 2.1, …);
    * seller and buyer with the identifiers each country prints (ΑΦΜ and
      ΔΟΥ in Greece, Steuernummer / USt-IdNr. in Germany and Austria,
      SIREN/SIRET and VAT number in France and Monaco, UID in Switzerland,
      enterprise number in Belgium, EIN in the US);
    * lines with their rate, exemption reasons, VAT breakdown by rate and
      totals (sales tax wording in the US);
    * legal mentions: the small business exemption of the seller's
      country (§ 19 UStG, art. 293 B du CGI, …), French B2B invoice
      mentions, the corrected document of a credit note;
    * the authority block (myDATA MARK, UID, authentication code, QR link)
      or a pending notice for Greek documents not yet accepted;
    * bank details, and the Swiss QR-bill for CH/LI invoices to be paid.
  """

  alias Palee.Fiscal.Domain.{
    CountryProfile,
    DocumentLabels,
    Iban,
    MyDataInvoice,
    QrBill,
    QrCode,
    TaxCategories
  }

  @doc """
  The view of `document`. Options: `:labels` (translated), `:language`,
  `:original` (the corrected document), `:transmission`, `:identity` (the
  seller's current identity, for bank details).
  """
  def build(document, opts \\ []) do
    labels = Keyword.get(opts, :labels, %{})
    language = Keyword.get(opts, :language) || document.language || "en"
    country = document.country_code
    format = %{language: language, country: country}
    label = &DocumentLabels.get(labels, &1)
    seller = stringify(document.seller)
    buyer = document.buyer && stringify(document.buyer)
    identity = Keyword.get(opts, :identity) || %{}
    original = Keyword.get(opts, :original)
    transmission = Keyword.get(opts, :transmission)
    sales_tax? = country == "US"
    title = title(document, original, label)

    %{
      language: language,
      title: title,
      number: document.number,
      meta: meta(document, original, label, format),
      seller: party(seller, country, label),
      buyer: buyer && party(buyer, country, label),
      seller_heading: label.(:seller),
      buyer_heading: label.(:buyer),
      columns: columns(document, label, sales_tax?),
      lines: Enum.map(document.lines, &line(&1, document, label, format)),
      show_discount: Enum.any?(document.lines, &((&1.discount_cents || 0) > 0)),
      breakdown_heading: if(sales_tax?, do: label.(:sales_tax), else: label.(:breakdown)),
      breakdown_columns: [
        label.(:rate),
        label.(:net),
        if(sales_tax?, do: label.(:sales_tax), else: label.(:tax)),
        label.(:gross)
      ],
      breakdown: breakdown(document, label, format),
      totals: totals(document, label, format, sales_tax?),
      mentions: mentions(document, seller, buyer, label),
      authority: authority(document, transmission, label),
      bank: bank(document, identity, label),
      qr_bill: qr_bill(document, identity, language, "#{title} #{document.number}"),
      footer: [label.(:footer_journal)],
      fingerprint: {label.(:fingerprint), document.content_hash},
      page_label: label.(:page)
    }
  end

  # ── Header ────────────────────────────────────────────────────────────────

  defp title(%{country_code: "GR"} = document, original, label) do
    case MyDataInvoice.invoice_type(document, original && original.kind) do
      "11.1" -> label.(:gr_11_1)
      "11.2" -> label.(:gr_11_2)
      "11.4" -> label.(:gr_11_4)
      "1." <> _zone -> label.(:gr_1_1)
      "2." <> _zone -> label.(:gr_2_1)
      "5.1" -> label.(:gr_5_1)
      _other -> kind_title(document.kind, label)
    end
  end

  defp title(document, _original, label), do: kind_title(document.kind, label)

  defp kind_title("invoice", label), do: label.(:title_invoice)
  defp kind_title("credit_note", label), do: label.(:title_credit_note)
  defp kind_title(_kind, label), do: label.(:title_receipt)

  defp meta(document, original, label, format) do
    [
      {label.(:number), document.number},
      {label.(:issue_date), date(document.issue_date, format)},
      document.payment_method &&
        {label.(:payment_method), payment_method(document.payment_method, label)},
      document.corrects_document_id &&
        {label.(:corrects), corrects(original, document.corrects_document_id, format)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp corrects(nil, id, _format), do: id

  defp corrects(original, _id, format),
    do: "#{original.number} (#{date(original.issue_date, format)})"

  defp payment_method(method, label) do
    case method do
      "cash" -> label.(:pm_cash)
      "card" -> label.(:pm_card)
      "bank_transfer" -> label.(:pm_bank_transfer)
      "online" -> label.(:pm_online)
      _other -> label.(:pm_other)
    end
  end

  # ── Parties ───────────────────────────────────────────────────────────────

  defp party(data, country, label) do
    name = data["legal_name"] || data["name"]
    trade = data["trade_name"]

    street =
      [data["street"], data["building_number"]] |> Enum.reject(&blank?/1) |> Enum.join(" ")

    place =
      case country do
        "US" ->
          [data["city"], [data["region"], data["postal_code"]] |> compact() |> Enum.join(" ")]
          |> compact()
          |> Enum.join(", ")

        "GB" ->
          [data["city"], data["postal_code"]] |> compact() |> Enum.join(" ")

        _other ->
          [data["postal_code"], data["city"]] |> compact() |> Enum.join(" ")
      end

    %{
      name: name,
      lines:
        compact([
          if(trade && trade != name, do: trade),
          street,
          place,
          if(data["country_code"] != country, do: data["country_code"])
        ]),
      ids: ids(data, country, label),
      contact:
        compact([
          data["email"] && "#{label.(:email)}: #{data["email"]}",
          data["phone"] && "#{label.(:phone)}: #{data["phone"]}"
        ])
    }
  end

  defp ids(data, country, label) do
    [:tax_id, :tax_office, :vat_number, :registration_number]
    |> Enum.flat_map(fn field ->
      case data[Atom.to_string(field)] do
        value when is_binary(value) and value != "" -> [{label.(id_label(country, field)), value}]
        _none -> []
      end
    end)
  end

  defp id_label("GR", :tax_id), do: :tax_id_gr
  defp id_label("GR", :tax_office), do: :tax_office_gr
  defp id_label("US", :tax_id), do: :ein
  defp id_label("BE", :tax_id), do: :enterprise_number
  defp id_label(country, :tax_id) when country in ["CH", "LI"], do: :uid
  defp id_label(country, :registration_number) when country in ["FR", "MC"], do: :siren
  defp id_label(_country, :tax_id), do: :tax_number
  defp id_label(_country, :tax_office), do: :tax_office_gr
  defp id_label(_country, :vat_number), do: :vat_number
  defp id_label(_country, :registration_number), do: :registration_number

  # ── Lines and totals ──────────────────────────────────────────────────────

  defp columns(_document, label, sales_tax?) do
    %{
      description: label.(:col_description),
      quantity: label.(:col_quantity),
      unit_price: label.(:col_unit_price),
      discount: label.(:col_discount),
      rate: if(sales_tax?, do: label.(:sales_tax), else: label.(:col_tax_rate)),
      amount: label.(:col_amount)
    }
  end

  defp line(line, document, label, format) do
    %{
      position: line.position,
      description: line.description,
      note:
        if(line.tax_category == "exempt" and line.exemption_reason,
          do: "#{label.(:exempt)}: #{line.exemption_reason}"
        ),
      quantity: Integer.to_string(line.quantity),
      unit_price: money(line.unit_price_cents, document.currency, format),
      discount:
        if((line.discount_cents || 0) > 0,
          do: money(line.discount_cents, document.currency, format),
          else: ""
        ),
      rate: rate_label(line.tax_category, line.rate_bp, label, format),
      amount: money(line.amount_cents, document.currency, format)
    }
  end

  defp breakdown(document, label, format) do
    Enum.map(document.tax_breakdown || [], fn group ->
      group = stringify(group)

      [
        rate_label(group["tax_category"], group["rate_bp"], label, format),
        money(group["net_cents"], document.currency, format),
        money(group["tax_cents"], document.currency, format),
        money(group["gross_cents"], document.currency, format)
      ]
    end)
  end

  defp totals(document, label, format, sales_tax?) do
    [
      {if(sales_tax?, do: label.(:subtotal), else: label.(:total_net)),
       money(document.net_cents, document.currency, format), false},
      {if(sales_tax?, do: label.(:total_sales_tax), else: label.(:total_tax)),
       money(document.tax_cents, document.currency, format), false},
      {label.(:total_gross), money(document.gross_cents, document.currency, format), true}
    ]
  end

  defp rate_label("exempt", _rate, label, _format), do: label.(:exempt)
  defp rate_label("zero", _rate, label, _format), do: label.(:zero_rated)
  defp rate_label(_category, rate, _label, format), do: percent(rate, format)

  # ── Mentions, authority, payment ──────────────────────────────────────────

  defp mentions(document, seller, buyer, label) do
    country = document.country_code

    small_business =
      if seller["vat_scheme"] == "small_business",
        do: TaxCategories.small_business_reason(country)

    french =
      if country in ["FR", "MC"] and document.kind == "invoice" do
        business_buyer? = buyer && (buyer["vat_number"] || buyer["tax_id"])
        [label.(:fr_operation), if(business_buyer?, do: label.(:fr_late_payment))]
      else
        []
      end

    compact([small_business | french])
  end

  defp authority(document, transmission, label) do
    profile = CountryProfile.fetch!(document.country_code)

    cond do
      transmission && transmission[:mark] ->
        %{
          title: label.(:mydata_title),
          rows:
            compact([
              {label.(:mydata_mark), transmission[:mark]},
              transmission[:uid] && {label.(:mydata_uid), transmission[:uid]},
              transmission[:authentication_code] &&
                {label.(:mydata_auth), transmission[:authentication_code]}
            ]),
          qr: qr(transmission[:qr_url]),
          qr_url: transmission[:qr_url],
          pending: nil
        }

      profile.authority == :mydata ->
        %{title: label.(:mydata_title), rows: [], qr: nil, qr_url: nil, pending: label.(:mydata_pending)}

      true ->
        nil
    end
  end

  defp qr(nil), do: nil

  defp qr(url) do
    case QrCode.modules(url) do
      {:ok, modules} -> modules
      _error -> nil
    end
  end

  defp bank(document, identity, label) do
    iban = identity[:iban]

    if document.kind == "invoice" and document.payment_method in [nil, "bank_transfer"] and
         is_binary(iban) do
      %{title: label.(:bank_details), rows: [{label.(:iban), Iban.format(iban)}]}
    end
  end

  defp qr_bill(document, identity, language, message) do
    case QrBill.for_document(document, identity, message) do
      nil ->
        nil

      bill ->
        case QrCode.modules(bill.payload, :m) do
          {:ok, modules} ->
            Map.merge(bill, %{qr: modules, headings: QrBill.headings(qr_language(language))})

          _error ->
            nil
        end
    end
  end

  defp qr_language(language) when language in ["de", "fr", "it"], do: language
  defp qr_language(_language), do: "en"

  # ── Formatting ────────────────────────────────────────────────────────────

  @doc """
  Money as printed: `1.234,56 EUR` (de, el, es, it, nl), `1 234,56 EUR`
  (fr), `1,234.56 USD` (en), `1'234.56 CHF` (Swiss and Liechtenstein
  documents in every language).
  """
  def money(nil, _currency, _format), do: ""

  def money(cents, currency, format) do
    {thousands, decimal} = separators(format)
    sign = if cents < 0, do: "-", else: ""
    absolute = abs(cents)

    units =
      absolute
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(thousands, &Enum.join/1)
      |> String.reverse()

    fraction = absolute |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}#{units}#{decimal}#{fraction} #{currency}"
  end

  defp separators(%{country: country}) when country in ["CH", "LI"], do: {"'", "."}
  defp separators(%{language: "en"}), do: {",", "."}
  defp separators(%{language: "fr"}), do: {" ", ","}
  defp separators(_format), do: {".", ","}

  @doc "A date as printed: 31.01.2027 (de), 01/31/2027 (US), 31-01-2027 (nl), else 31/01/2027."
  def date(nil, _format), do: ""

  def date(%Date{} = date, format) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    year = Integer.to_string(date.year)

    cond do
      format.country == "US" -> "#{month}/#{day}/#{year}"
      format.language == "de" -> "#{day}.#{month}.#{year}"
      format.language == "nl" -> "#{day}-#{month}-#{year}"
      true -> "#{day}/#{month}/#{year}"
    end
  end

  @doc "A rate in basis points as printed: `24%`, `8,1%` (comma languages), `8.1%`."
  def percent(nil, _format), do: ""

  def percent(bp, format) do
    {_thousands, decimal} = separators(format)
    whole = div(bp, 100)

    fraction =
      bp |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0") |> String.trim_trailing("0")

    if fraction == "", do: "#{whole}%", else: "#{whole}#{decimal}#{fraction}%"
  end

  @doc "Escapes the five HTML-significant characters."
  def escape(nil), do: ""

  def escape(value) when is_binary(value) do
    for <<char <- value>>, into: "" do
      case char do
        ?& -> "&amp;"
        ?< -> "&lt;"
        ?> -> "&gt;"
        ?" -> "&quot;"
        ?' -> "&#39;"
        other -> <<other>>
      end
    end
  end

  def escape(value), do: value |> to_string() |> escape()

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp compact(list), do: Enum.reject(list, &blank?/1)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
