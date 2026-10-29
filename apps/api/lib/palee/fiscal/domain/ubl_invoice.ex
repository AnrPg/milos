defmodule Palee.Fiscal.Domain.UblInvoice do
  @moduledoc """
  Maps a fiscal document to a UBL 2.1 `Invoice` or `CreditNote` that
  conforms to EN 16931 and Peppol BIS Billing 3.0 (ADR-250). Pure.

  The result is an element tree that `Infrastructure.Fiscal.Peppol.UblWriter`
  writes as XML:

    * `{name, text}` – a leaf (`name` such as `"cbc:ID"`);
    * `{name, attributes, text}` – a leaf with attributes
      (`[currencyID: "EUR"]`);
    * `{name, children}` – an aggregate.

  Element order follows the UBL 2.1 schemas. What the document says is
  never recomputed: amounts are the document's (positive also on credit
  notes, as BIS requires), VAT by rate group is its `tax_breakdown`.

  Choices that the BIS leaves to the sender:

    * line prices are net (BT-146). When a line's net amount does not
      divide by its quantity, the price is given for the whole quantity
      (`BaseQuantity` = quantity), so quantity × price ÷ base quantity is
      the line amount to the cent (PEPPOL-EN16931-R120);
    * the buyer reference (BT-10, PEPPOL-EN16931-R003) is the buyer's own
      reference when known, else the document number;
    * documents paid at the desk or online carry the paid amount (BT-113)
      and nothing left to pay; others are due on receipt (BT-9 / BT-20,
      BR-CO-25);
    * VAT categories: a positive rate is `S`, `zero` is `Z`, `exempt` is
      `E` with the document's exemption reason (BR-E-10).

  Sources: Peppol BIS Billing 3.0 (https://docs.peppol.eu/poacc/billing/3.0/),
  EN 16931-1, OASIS UBL 2.1 (https://docs.oasis-open.org/ubl/os-UBL-2.1/).
  """

  @customization "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
  @profile "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"
  @unit "C62"
  @paid_methods ~w(cash card online)
  # UNCL 4461 payment means.
  @means %{"cash" => "10", "card" => "54", "online" => "68", "other" => "1"}
  @payable_on_receipt %{
    "fr" => "Payable à réception",
    "nl" => "Betaalbaar bij ontvangst",
    "de" => "Zahlbar bei Erhalt",
    "en" => "Payable on receipt"
  }

  def customization_id, do: @customization
  def profile_id, do: @profile

  @doc "`\"Invoice\"` or `\"CreditNote\"`: the UBL document type of a fiscal document."
  def document_type(%{kind: "credit_note"}), do: "CreditNote"
  def document_type(_document), do: "Invoice"

  @doc """
  `{:ok, {root_name, children}}` or `{:error, reason}`.

  Options:
    * `:seller_endpoint` – `%{scheme, identifier}` (required, BT-34);
    * `:buyer_endpoint` – `%{scheme, identifier}` (required, BT-49);
    * `:original` – `%{number, issue_date}` of the corrected invoice
      (credit notes, BT-25/BT-26).
  """
  def build(document, opts) do
    with :ok <- supported(document),
         {:ok, seller_endpoint} <- endpoint(opts[:seller_endpoint], :seller_peppol_id_missing),
         {:ok, buyer_endpoint} <- endpoint(opts[:buyer_endpoint], :buyer_peppol_id_missing),
         {:ok, lines} <- lines(document),
         :ok <- credit_reference(document, opts[:original]) do
      currency = document.currency
      credit? = document.kind == "credit_note"
      paid? = document.payment_method in @paid_methods
      gross = document.gross_cents

      children =
        [
          {"cbc:CustomizationID", @customization},
          {"cbc:ProfileID", @profile},
          {"cbc:ID", document.number},
          {"cbc:IssueDate", Date.to_iso8601(document.issue_date)}
        ] ++
          if(credit? or paid?,
            do: [],
            else: [{"cbc:DueDate", Date.to_iso8601(document.issue_date)}]
          ) ++
          [
            {if(credit?, do: "cbc:CreditNoteTypeCode", else: "cbc:InvoiceTypeCode"),
             if(credit?, do: "381", else: "380")},
            {"cbc:DocumentCurrencyCode", currency},
            {"cbc:BuyerReference", buyer_reference(document)}
          ] ++
          billing_reference(document, opts[:original]) ++
          [
            {"cac:AccountingSupplierParty", [seller_party(document, seller_endpoint)]},
            {"cac:AccountingCustomerParty", [buyer_party(document, buyer_endpoint)]}
          ] ++
          payment_means(document) ++
          payment_terms(document, paid?) ++
          [
            {"cac:TaxTotal",
             [
               {"cbc:TaxAmount", [currencyID: currency], amount(document.tax_cents)}
               | Enum.map(document.tax_breakdown, &tax_subtotal(&1, document, currency))
             ]},
            {"cac:LegalMonetaryTotal",
             [
               {"cbc:LineExtensionAmount", [currencyID: currency], amount(document.net_cents)},
               {"cbc:TaxExclusiveAmount", [currencyID: currency], amount(document.net_cents)},
               {"cbc:TaxInclusiveAmount", [currencyID: currency], amount(gross)}
             ] ++
               if(paid? and not credit?,
                 do: [
                   {"cbc:PrepaidAmount", [currencyID: currency], amount(gross)},
                   {"cbc:PayableAmount", [currencyID: currency], amount(0)}
                 ],
                 else: [{"cbc:PayableAmount", [currencyID: currency], amount(gross)}]
               )}
          ] ++ Enum.map(lines, &line(&1, credit?, currency))

      {:ok, {document_type(document), children}}
    end
  end

  # ── Checks ──────────────────────────────────────────────────────────────

  defp supported(%{kind: kind}) when kind in ["invoice", "credit_note"], do: :ok
  defp supported(_document), do: {:error, :not_an_invoice}

  defp endpoint(%{scheme: scheme, identifier: identifier} = endpoint, _error)
       when is_binary(scheme) and is_binary(identifier),
       do: {:ok, endpoint}

  defp endpoint(_endpoint, error), do: {:error, error}

  defp lines(%{lines: [_ | _] = lines}), do: {:ok, Enum.sort_by(lines, & &1.position)}
  defp lines(_document), do: {:error, :no_lines}

  defp credit_reference(%{kind: "credit_note"}, %{number: number}) when is_binary(number),
    do: :ok

  defp credit_reference(%{kind: "credit_note"}, _original), do: {:error, :original_missing}
  defp credit_reference(_document, _original), do: :ok

  # ── Header ──────────────────────────────────────────────────────────────

  defp buyer_reference(document) do
    case document.buyer do
      %{reference: reference} when is_binary(reference) and reference != "" -> reference
      _buyer -> document.number
    end
  end

  defp billing_reference(%{kind: "credit_note"}, original) do
    [
      {"cac:BillingReference",
       [
         {"cac:InvoiceDocumentReference",
          [{"cbc:ID", original.number}] ++
            case original[:issue_date] do
              %Date{} = date -> [{"cbc:IssueDate", Date.to_iso8601(date)}]
              _none -> []
            end}
       ]}
    ]
  end

  defp billing_reference(_document, _original), do: []

  defp payment_means(%{payment_method: method}) when is_map_key(@means, method),
    do: [{"cac:PaymentMeans", [{"cbc:PaymentMeansCode", Map.fetch!(@means, method)}]}]

  defp payment_means(_document), do: []

  defp payment_terms(%{kind: "credit_note"} = document, _paid?), do: terms(document)
  defp payment_terms(_document, true), do: []
  defp payment_terms(document, false), do: terms(document)

  defp terms(document) do
    [
      {"cac:PaymentTerms",
       [
         {"cbc:Note",
          Map.get(@payable_on_receipt, document.language, @payable_on_receipt["en"])}
       ]}
    ]
  end

  # ── Parties ─────────────────────────────────────────────────────────────

  defp seller_party(document, endpoint) do
    seller = atomize(document.seller)
    vat = seller_vat(seller)

    {"cac:Party",
     [
       {"cbc:EndpointID", [schemeID: endpoint.scheme], endpoint.identifier},
       {"cac:PartyName", [{"cbc:Name", seller[:trade_name] || seller[:legal_name]}]},
       address(seller, document.country_code)
     ] ++
       if(vat, do: [party_tax_scheme(vat)], else: []) ++
       [
         {"cac:PartyLegalEntity",
          [{"cbc:RegistrationName", seller[:legal_name]}] ++
            legal_id(seller, document.country_code)}
       ] ++ contact(seller)}
  end

  defp buyer_party(document, endpoint) do
    buyer = atomize(document.buyer || %{})

    {"cac:Party",
     [
       {"cbc:EndpointID", [schemeID: endpoint.scheme], endpoint.identifier},
       address(buyer, buyer[:country_code] || document.country_code)
     ] ++
       case buyer[:vat_number] do
         vat when is_binary(vat) -> [party_tax_scheme(vat_with_prefix(vat, buyer))]
         _none -> []
       end ++
       [{"cac:PartyLegalEntity", [{"cbc:RegistrationName", buyer[:name] || "-"}]}] ++
       contact(buyer)}
  end

  defp address(party, country) do
    street =
      [party[:street], party[:building_number]]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" ")

    {"cac:PostalAddress",
     Enum.reject(
       [
         if(street != "", do: {"cbc:StreetName", street}),
         if(!blank?(party[:city]), do: {"cbc:CityName", party[:city]}),
         if(!blank?(party[:postal_code]), do: {"cbc:PostalZone", party[:postal_code]}),
         if(!blank?(party[:region]), do: {"cbc:CountrySubentity", party[:region]}),
         {"cac:Country", [{"cbc:IdentificationCode", country}]}
       ],
       &is_nil/1
     )}
  end

  defp party_tax_scheme(vat) do
    {"cac:PartyTaxScheme", [{"cbc:CompanyID", vat}, {"cac:TaxScheme", [{"cbc:ID", "VAT"}]}]}
  end

  defp legal_id(seller, "BE") do
    case Palee.Fiscal.Domain.PeppolId.be_number(seller[:tax_id] || seller[:vat_number]) do
      nil -> []
      number -> [{"cbc:CompanyID", [schemeID: "0208"], number}]
    end
  end

  defp legal_id(_seller, _country), do: []

  defp contact(party) do
    case party[:email] do
      email when is_binary(email) and email != "" ->
        [{"cac:Contact", [{"cbc:ElectronicMail", email}]}]

      _none ->
        []
    end
  end

  # BR-CO-9: VAT identifiers carry their country prefix.
  defp seller_vat(seller) do
    cond do
      Map.get(seller, :vat_scheme, "standard") != "standard" and blank?(seller[:vat_number]) ->
        nil

      is_binary(seller[:vat_number]) ->
        vat_with_prefix(seller.vat_number, seller)

      seller[:country_code] == "BE" ->
        case Palee.Fiscal.Domain.PeppolId.be_number(seller[:tax_id]) do
          nil -> nil
          number -> "BE" <> number
        end

      true ->
        nil
    end
  end

  defp vat_with_prefix(vat, party) do
    vat = vat |> String.upcase() |> String.replace(~r/[\s.\-]/, "")

    if Regex.match?(~r/^[A-Z]{2}/, vat),
      do: vat,
      else: (party[:country_code] || "") <> vat
  end

  # ── Tax ─────────────────────────────────────────────────────────────────

  defp tax_subtotal(group, document, currency) do
    group = atomize(group)

    {"cac:TaxSubtotal",
     [
       {"cbc:TaxableAmount", [currencyID: currency], amount(group.net_cents)},
       {"cbc:TaxAmount", [currencyID: currency], amount(group.tax_cents)},
       {"cac:TaxCategory",
        [
          {"cbc:ID", category(group.tax_category, group.rate_bp)},
          {"cbc:Percent", percent(group.rate_bp)}
        ] ++
          exemption(group, document) ++ [{"cac:TaxScheme", [{"cbc:ID", "VAT"}]}]}
     ]}
  end

  defp exemption(%{tax_category: "exempt"} = group, document) do
    reason =
      document.lines
      |> Enum.find_value(fn line ->
        if line.tax_category == "exempt" and line.rate_bp == group.rate_bp,
          do: line.exemption_reason
      end)

    [{"cbc:TaxExemptionReason", reason || "Exempt"}]
  end

  defp exemption(_group, _document), do: []

  @doc "The EN 16931 VAT category code (UNCL 5305) of a Palee tax category."
  def category("exempt", _rate), do: "E"
  def category("zero", _rate), do: "Z"
  def category(_category, 0), do: "Z"
  def category(_category, _rate), do: "S"

  # ── Lines ───────────────────────────────────────────────────────────────

  defp line(line, credit?, currency) do
    {price, base} =
      if rem(line.net_cents, line.quantity) == 0,
        do: {div(line.net_cents, line.quantity), nil},
        else: {line.net_cents, line.quantity}

    {if(credit?, do: "cac:CreditNoteLine", else: "cac:InvoiceLine"),
     [
       {"cbc:ID", Integer.to_string(line.position)},
       {if(credit?, do: "cbc:CreditedQuantity", else: "cbc:InvoicedQuantity"), [unitCode: @unit],
        Integer.to_string(line.quantity)},
       {"cbc:LineExtensionAmount", [currencyID: currency], amount(line.net_cents)},
       {"cac:Item",
        [
          {"cbc:Name", String.slice(line.description, 0, 200)},
          {"cac:ClassifiedTaxCategory",
           [
             {"cbc:ID", category(line.tax_category, line.rate_bp)},
             {"cbc:Percent", percent(line.rate_bp)},
             {"cac:TaxScheme", [{"cbc:ID", "VAT"}]}
           ]}
        ]},
       {"cac:Price",
        [{"cbc:PriceAmount", [currencyID: currency], amount(price)}] ++
          if(base,
            do: [{"cbc:BaseQuantity", [unitCode: @unit], Integer.to_string(base)}],
            else: []
          )}
     ]}
  end

  # ── Formatting ──────────────────────────────────────────────────────────

  @doc "Cents as a decimal amount with two decimals (`1234` → `\"12.34\"`)."
  def amount(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    sign <>
      Integer.to_string(div(cents, 100)) <>
      "." <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
  end

  @doc "Basis points as a percentage without trailing zeros (`2100` → `\"21\"`, `810` → `\"8.1\"`)."
  def percent(bp) when is_integer(bp) do
    whole = Integer.to_string(div(bp, 100))

    case rem(bp, 100) do
      0 -> whole
      fraction -> whole <> "." <> (fraction |> Integer.to_string() |> String.pad_leading(2, "0") |> String.trim_trailing("0"))
    end
  end

  defp atomize(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
