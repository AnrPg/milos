defmodule Palee.PeppolBisRules do
  @moduledoc """
  ADR-250: the EN 16931 / Peppol BIS Billing 3.0 business rules that
  Palee's invoices and credit notes touch, checked on the generated XML.

  The official Schematron needs an XSLT 2 processor that the test
  environment does not have; this module re-states the rules (same
  identifiers, https://docs.peppol.eu/poacc/billing/3.0/rules/) so that
  every generated document is checked in CI. `check/1` returns the ids of
  the broken rules (`[]` when the document is valid).
  """

  require Record

  Record.defrecordp(:xml_element, :xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecordp(:xml_text, :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  Record.defrecordp(
    :xml_attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @customization "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
  @profile "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

  @doc "Parses the XML into `{name, attributes, children | text}` nodes."
  def parse(xml) do
    {document, _rest} = xml |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)
    to_node(document)
  end

  defp to_node(element) when Record.is_record(element, :xmlElement) do
    name = element |> xml_element(:name) |> Atom.to_string()

    attributes =
      element
      |> xml_element(:attributes)
      |> Map.new(fn attribute ->
        {attribute |> xml_attribute(:name) |> Atom.to_string(),
         attribute |> xml_attribute(:value) |> List.to_string()}
      end)

    children = xml_element(element, :content)

    elements = Enum.filter(children, &Record.is_record(&1, :xmlElement))

    if elements == [] do
      text =
        children
        |> Enum.filter(&Record.is_record(&1, :xmlText))
        |> Enum.map_join(&(&1 |> xml_text(:value) |> List.to_string()))

      {name, attributes, text}
    else
      {name, attributes, Enum.map(elements, &to_node/1)}
    end
  end

  @doc "Children named `name` (a path like `\"cac:TaxTotal/cac:TaxSubtotal\"`)."
  def all(node, path) do
    path
    |> String.split("/")
    |> Enum.reduce([node], fn name, nodes ->
      Enum.flat_map(nodes, fn
        {_name, _attributes, children} when is_list(children) ->
          Enum.filter(children, &match?({^name, _, _}, &1))

        _leaf ->
          []
      end)
    end)
  end

  def one(node, path), do: node |> all(path) |> List.first()

  def text(node, path) do
    case one(node, path) do
      {_name, _attributes, text} when is_binary(text) -> text
      _other -> nil
    end
  end

  defp cents(nil), do: nil

  defp cents(text) do
    text |> Decimal.new() |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
  end

  defp decimal(nil), do: nil
  defp decimal(text), do: Decimal.new(text)

  @doc "The ids of broken rules."
  def check(xml) when is_binary(xml) do
    root = parse(xml)
    {root_name, _attributes, _children} = root
    credit? = root_name == "CreditNote"
    line_name = if credit?, do: "cac:CreditNoteLine", else: "cac:InvoiceLine"
    quantity_name = if credit?, do: "cbc:CreditedQuantity", else: "cbc:InvoicedQuantity"
    currency = text(root, "cbc:DocumentCurrencyCode")
    lines = all(root, line_name)
    totals = one(root, "cac:LegalMonetaryTotal")
    subtotals = all(root, "cac:TaxTotal/cac:TaxSubtotal")
    seller = one(root, "cac:AccountingSupplierParty/cac:Party")
    buyer = one(root, "cac:AccountingCustomerParty/cac:Party")

    line_sum = lines |> Enum.map(&cents(text(&1, "cbc:LineExtensionAmount"))) |> Enum.sum()
    line_extension = cents(text(totals, "cbc:LineExtensionAmount"))
    tax_exclusive = cents(text(totals, "cbc:TaxExclusiveAmount"))
    tax_inclusive = cents(text(totals, "cbc:TaxInclusiveAmount"))
    prepaid = cents(text(totals, "cbc:PrepaidAmount")) || 0
    rounding = cents(text(totals, "cbc:PayableRoundingAmount")) || 0
    payable = cents(text(totals, "cbc:PayableAmount"))
    tax_total = cents(text(root, "cac:TaxTotal/cbc:TaxAmount"))
    categories = Enum.map(subtotals, &text(&1, "cac:TaxCategory/cbc:ID"))

    [
      {"PEPPOL-EN16931-R004", text(root, "cbc:CustomizationID") == @customization},
      {"PEPPOL-EN16931-R007", text(root, "cbc:ProfileID") == @profile},
      {"BR-02", present?(text(root, "cbc:ID"))},
      {"BR-03", present?(text(root, "cbc:IssueDate"))},
      {"BR-04",
       text(root, if(credit?, do: "cbc:CreditNoteTypeCode", else: "cbc:InvoiceTypeCode")) in [
         "380",
         "381"
       ]},
      {"BR-05", present?(currency)},
      {"PEPPOL-EN16931-R003",
       present?(text(root, "cbc:BuyerReference")) or
         present?(text(root, "cac:OrderReference/cbc:ID"))},
      {"BR-06", present?(text(seller, "cac:PartyLegalEntity/cbc:RegistrationName"))},
      {"BR-07", present?(text(buyer, "cac:PartyLegalEntity/cbc:RegistrationName"))},
      {"BR-09", present?(text(seller, "cac:PostalAddress/cac:Country/cbc:IdentificationCode"))},
      {"BR-11", present?(text(buyer, "cac:PostalAddress/cac:Country/cbc:IdentificationCode"))},
      {"BR-16", lines != []},
      {"BR-62", endpoint?(seller)},
      {"BR-63", endpoint?(buyer)},
      {"PEPPOL-EN16931-R020", present?(text(seller, "cbc:EndpointID"))},
      {"PEPPOL-EN16931-R010", present?(text(buyer, "cbc:EndpointID"))},
      {"BR-CO-9", vat_prefixed?(seller) and vat_prefixed?(buyer)},
      {"BR-CO-10", line_sum == line_extension},
      {"BR-CO-13", tax_exclusive == line_extension},
      {"BR-CO-14",
       tax_total == subtotals |> Enum.map(&cents(text(&1, "cbc:TaxAmount"))) |> Enum.sum()},
      {"BR-CO-15", tax_inclusive == tax_exclusive + tax_total},
      {"BR-CO-16", payable == tax_inclusive - prepaid + rounding},
      {"BR-CO-17", Enum.all?(subtotals, &category_tax_ok?/1)},
      {"BR-CO-18", subtotals != []},
      {"BR-CO-25",
       payable <= 0 or present?(text(root, "cbc:DueDate")) or
         present?(text(root, "cac:PaymentTerms/cbc:Note"))},
      {"BR-S-02", "S" not in categories or seller_vat?(seller)},
      {"BR-E-02", "E" not in categories or seller_vat?(seller)},
      {"BR-S-08", category_bases_ok?(subtotals, lines, "S")},
      {"BR-Z-08", category_bases_ok?(subtotals, lines, "Z")},
      {"BR-E-08", category_bases_ok?(subtotals, lines, "E")},
      {"BR-E-10",
       Enum.all?(subtotals, fn subtotal ->
         text(subtotal, "cac:TaxCategory/cbc:ID") != "E" or
           present?(text(subtotal, "cac:TaxCategory/cbc:TaxExemptionReason")) or
           present?(text(subtotal, "cac:TaxCategory/cbc:TaxExemptionReasonCode"))
       end)},
      {"BR-S-05",
       Enum.all?(lines, fn line ->
         text(line, "cac:Item/cac:ClassifiedTaxCategory/cbc:ID") != "S" or
           Decimal.gt?(decimal(text(line, "cac:Item/cac:ClassifiedTaxCategory/cbc:Percent")), 0)
       end)},
      {"BR-21..BR-26",
       Enum.all?(lines, fn line ->
         present?(text(line, "cbc:ID")) and present?(text(line, quantity_name)) and
           present?(text(line, "cbc:LineExtensionAmount")) and
           present?(text(line, "cac:Item/cbc:Name")) and
           present?(text(line, "cac:Price/cbc:PriceAmount"))
       end)},
      {"BR-27", Enum.all?(lines, &(not Decimal.negative?(decimal(text(&1, "cac:Price/cbc:PriceAmount")))))},
      {"PEPPOL-EN16931-R120", Enum.all?(lines, &(line_amount_ok?(&1, quantity_name)))},
      {"PEPPOL-EN16931-R051", currencies_ok?(root, currency)},
      {"BR-55", not credit? or present?(text(root, "cac:BillingReference/cac:InvoiceDocumentReference/cbc:ID"))}
    ]
    |> Enum.reject(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp endpoint?(party) do
    case one(party, "cbc:EndpointID") do
      {_name, %{"schemeID" => scheme}, id} -> present?(scheme) and present?(id)
      _other -> false
    end
  end

  defp vat_prefixed?(party) do
    party
    |> all("cac:PartyTaxScheme")
    |> Enum.filter(&(text(&1, "cac:TaxScheme/cbc:ID") == "VAT"))
    |> Enum.all?(&Regex.match?(~r/^[A-Z]{2}/, text(&1, "cbc:CompanyID") || ""))
  end

  defp seller_vat?(seller) do
    seller
    |> all("cac:PartyTaxScheme")
    |> Enum.any?(&(text(&1, "cac:TaxScheme/cbc:ID") == "VAT" and present?(text(&1, "cbc:CompanyID"))))
  end

  # BR-CO-17 in the official Schematron allows one currency unit either way.
  defp category_tax_ok?(subtotal) do
    taxable = decimal(text(subtotal, "cbc:TaxableAmount"))
    tax = decimal(text(subtotal, "cbc:TaxAmount"))
    rate = decimal(text(subtotal, "cac:TaxCategory/cbc:Percent")) || Decimal.new(0)
    expected = taxable |> Decimal.mult(rate) |> Decimal.div(100) |> Decimal.round(2)
    Decimal.compare(tax |> Decimal.sub(expected) |> Decimal.abs(), 1) == :lt
  end

  defp category_bases_ok?(subtotals, lines, category) do
    subtotals
    |> Enum.filter(&(text(&1, "cac:TaxCategory/cbc:ID") == category))
    |> Enum.all?(fn subtotal ->
      percent = decimal(text(subtotal, "cac:TaxCategory/cbc:Percent"))

      base =
        lines
        |> Enum.filter(fn line ->
          text(line, "cac:Item/cac:ClassifiedTaxCategory/cbc:ID") == category and
            Decimal.equal?(
              decimal(text(line, "cac:Item/cac:ClassifiedTaxCategory/cbc:Percent")),
              percent
            )
        end)
        |> Enum.map(&cents(text(&1, "cbc:LineExtensionAmount")))
        |> Enum.sum()

      base == cents(text(subtotal, "cbc:TaxableAmount"))
    end)
  end

  defp line_amount_ok?(line, quantity_name) do
    quantity = decimal(text(line, quantity_name))
    price = decimal(text(line, "cac:Price/cbc:PriceAmount"))
    base = decimal(text(line, "cac:Price/cbc:BaseQuantity")) || Decimal.new(1)

    computed = quantity |> Decimal.mult(price) |> Decimal.div(base) |> Decimal.round(2)
    Decimal.equal?(computed, decimal(text(line, "cbc:LineExtensionAmount")))
  end

  defp currencies_ok?(node, currency) do
    case node do
      {_name, attributes, children} when is_list(children) ->
        Map.get(attributes, "currencyID", currency) == currency and
          Enum.all?(children, &currencies_ok?(&1, currency))

      {_name, attributes, _text} ->
        Map.get(attributes, "currencyID", currency) == currency
    end
  end
end
