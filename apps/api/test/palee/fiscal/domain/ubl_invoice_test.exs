defmodule Palee.Fiscal.Domain.UblInvoiceTest do
  @moduledoc """
  ADR-250: Belgian invoices and credit notes become UBL 2.1 documents that
  are valid against the official OASIS schemas and the EN 16931 / Peppol
  BIS Billing 3.0 rules.
  """

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{FiscalDocumentPolicy, PeppolId, UblInvoice}
  alias Palee.Infrastructure.Fiscal.Peppol.UblWriter
  alias Palee.PeppolBisRules

  @xsd_dir Path.expand("../../../../priv/fiscal/ubl/2.1/maindoc", __DIR__)

  @identity %{
    legal_name: "Box Bruxelles SRL",
    trade_name: "CrossFit Bruxelles",
    country_code: "BE",
    tax_id: "0403.170.701",
    vat_number: "BE0403170701",
    vat_scheme: "standard",
    street: "Rue de la Loi",
    building_number: "16",
    postal_code: "1000",
    city: "Bruxelles",
    email: "billing@box.example",
    document_language: "fr",
    branch_code: 0
  }

  @buyer %{
    name: "Entreprise Cliente SA & Co <BE>",
    vat_number: "BE 0202.239.951",
    street: "Avenue Louise",
    building_number: "54",
    postal_code: "1050",
    city: "Ixelles",
    country_code: "BE"
  }

  @seller_endpoint %{scheme: "0208", identifier: "0403170701"}

  # A document shaped as the store returns it (JSON maps with string keys).
  defp issue(request) do
    {:ok, document} =
      FiscalDocumentPolicy.build(
        @identity,
        Map.merge(%{kind: "invoice", issue_date: ~D[2027-02-08], buyer: @buyer}, request)
      )

    stored(document, "I-000001")
  end

  defp stored(document, number) do
    %{
      document
      | seller: stringify(document.seller),
        buyer: document.buyer && stringify(document.buyer),
        tax_breakdown: Enum.map(document.tax_breakdown, &stringify/1)
    }
    |> Map.merge(%{id: Ecto.UUID.generate(), number: number})
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp xml(document, opts \\ []) do
    {:ok, buyer_endpoint} = PeppolId.for_party(atomize(document.buyer))

    {:ok, tree} =
      UblInvoice.build(
        document,
        Keyword.merge([seller_endpoint: @seller_endpoint, buyer_endpoint: buyer_endpoint], opts)
      )

    UblWriter.write(tree)
  end

  defp atomize(map), do: Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)

  defp lines(specs) do
    Enum.map(specs, fn {description, quantity, price, category} ->
      %{
        description: description,
        quantity: quantity,
        unit_price_cents: price,
        tax_category: category,
        exemption_reason: if(category == "exempt", do: "Article 44 § 2, 3° du Code TVA")
      }
    end)
  end

  defp documents do
    invoice =
      issue(%{
        payment_method: "bank_transfer",
        lines:
          lines([
            {"Abonnement mensuel", 1, 8_900, "standard"},
            {"Cours d'essai", 3, 1_000, "standard"},
            {"Boisson", 2, 250, "super_reduced"}
          ])
      })

    net_prices =
      issue(%{
        prices_include_tax: false,
        payment_method: "card",
        lines:
          lines([
            {"Coaching", 3, 3_333, "standard"},
            {"Séance sportive", 1, 1_500, "exempt"},
            {"Location", 7, 101, "zero"}
          ])
      })

    {:ok, credit} =
      FiscalDocumentPolicy.credit_note(
        Map.update!(invoice, :lines, &Enum.map(&1, fn line -> line end)),
        %{},
        [%{position: 2, quantity: 1}],
        ~D[2027-02-10]
      )

    credit = stored(credit, "C-000001")

    [
      {invoice, []},
      {net_prices, []},
      {credit, [original: %{number: invoice.number, issue_date: invoice.issue_date}]}
    ]
  end

  test "invoices and credit notes follow the EN 16931 / Peppol BIS rules" do
    for {document, opts} <- documents() do
      xml = xml(document, opts)
      assert PeppolBisRules.check(xml) == [], xml
    end
  end

  test "the rule check catches broken totals, references and endpoints" do
    [{invoice, _opts} | _rest] = documents()
    xml = xml(invoice)
    payable = UblInvoice.amount(invoice.gross_cents)

    broken =
      xml
      |> String.replace(
        ~s(<cbc:PayableAmount currencyID="EUR">#{payable}</cbc:PayableAmount>),
        ~s(<cbc:PayableAmount currencyID="EUR">1.00</cbc:PayableAmount>)
      )
      |> String.replace("<cbc:BuyerReference>I-000001</cbc:BuyerReference>", "")
      |> String.replace(~s(<cbc:EndpointID schemeID="0208">0202239951</cbc:EndpointID>), "")

    assert Enum.sort(PeppolBisRules.check(broken)) ==
             Enum.sort(["BR-CO-16", "PEPPOL-EN16931-R003", "BR-63", "PEPPOL-EN16931-R010"])
  end

  @tag :xmllint
  @tag :tmp_dir
  test "invoices and credit notes are valid UBL 2.1", %{tmp_dir: dir} do
    for {document, opts} <- documents() do
      xml = xml(document, opts)
      root = UblInvoice.document_type(document)
      path = Path.join(dir, "#{document.number}.xml")
      File.write!(path, xml)

      {output, status} =
        System.cmd(
          "xmllint",
          ["--noout", "--schema", Path.join(@xsd_dir, "UBL-#{root}-2.1.xsd"), path],
          stderr_to_stdout: true
        )

      assert status == 0, output
    end
  end

  test "the header, parties and totals carry the document's own values" do
    [{invoice, _opts} | _rest] = documents()
    root = invoice |> xml() |> PeppolBisRules.parse()

    assert PeppolBisRules.text(root, "cbc:ID") == "I-000001"
    assert PeppolBisRules.text(root, "cbc:InvoiceTypeCode") == "380"
    assert PeppolBisRules.text(root, "cbc:DueDate") == "2027-02-08"
    assert PeppolBisRules.text(root, "cac:PaymentTerms/cbc:Note") == "Payable à réception"

    seller = PeppolBisRules.one(root, "cac:AccountingSupplierParty/cac:Party")
    buyer = PeppolBisRules.one(root, "cac:AccountingCustomerParty/cac:Party")

    assert {"cbc:EndpointID", %{"schemeID" => "0208"}, "0403170701"} =
             PeppolBisRules.one(seller, "cbc:EndpointID")

    assert {"cbc:EndpointID", %{"schemeID" => "0208"}, "0202239951"} =
             PeppolBisRules.one(buyer, "cbc:EndpointID")

    assert PeppolBisRules.text(buyer, "cac:PartyTaxScheme/cbc:CompanyID") == "BE0202239951"

    assert PeppolBisRules.text(buyer, "cac:PartyLegalEntity/cbc:RegistrationName") ==
             "Entreprise Cliente SA & Co <BE>"

    assert PeppolBisRules.text(root, "cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount") ==
             UblInvoice.amount(invoice.gross_cents)

    assert PeppolBisRules.text(root, "cac:LegalMonetaryTotal/cbc:PayableAmount") ==
             UblInvoice.amount(invoice.gross_cents)

    assert PeppolBisRules.text(root, "cac:PaymentMeans/cbc:PaymentMeansCode") == nil
  end

  test "a document paid at the desk is fully prepaid" do
    [_invoice, {paid, _opts} | _rest] = documents()
    root = paid |> xml() |> PeppolBisRules.parse()

    assert PeppolBisRules.text(root, "cac:PaymentMeans/cbc:PaymentMeansCode") == "54"
    assert PeppolBisRules.text(root, "cac:LegalMonetaryTotal/cbc:PayableAmount") == "0.00"
    assert PeppolBisRules.text(root, "cbc:DueDate") == nil

    categories =
      root
      |> PeppolBisRules.all("cac:TaxTotal/cac:TaxSubtotal")
      |> Enum.map(&PeppolBisRules.text(&1, "cac:TaxCategory/cbc:ID"))

    assert Enum.sort(categories) == ["E", "S", "Z"]

    # 3 × 33.33 = 99.99: a whole-unit price; 7 × 1.01 likewise.
    [coaching | _] = PeppolBisRules.all(root, "cac:InvoiceLine")
    assert PeppolBisRules.text(coaching, "cac:Price/cbc:PriceAmount") == "33.33"
    assert PeppolBisRules.text(coaching, "cac:Price/cbc:BaseQuantity") == nil
  end

  test "a price that does not divide by the quantity is given for the whole quantity" do
    [{invoice, _opts} | _rest] = documents()
    root = invoice |> xml() |> PeppolBisRules.parse()

    uneven =
      root
      |> PeppolBisRules.all("cac:InvoiceLine")
      |> Enum.find(&PeppolBisRules.text(&1, "cac:Price/cbc:BaseQuantity"))

    assert uneven
    quantity = PeppolBisRules.text(uneven, "cbc:InvoicedQuantity")
    assert PeppolBisRules.text(uneven, "cac:Price/cbc:BaseQuantity") == quantity

    assert PeppolBisRules.text(uneven, "cac:Price/cbc:PriceAmount") ==
             PeppolBisRules.text(uneven, "cbc:LineExtensionAmount")
  end

  test "a credit note references the invoice it corrects" do
    [{invoice, _}, _paid, {credit, opts}] = documents()
    root = credit |> xml(opts) |> PeppolBisRules.parse()

    assert elem(root, 0) == "CreditNote"
    assert PeppolBisRules.text(root, "cbc:CreditNoteTypeCode") == "381"

    assert PeppolBisRules.text(root, "cac:BillingReference/cac:InvoiceDocumentReference/cbc:ID") ==
             invoice.number

    assert [line] = PeppolBisRules.all(root, "cac:CreditNoteLine")
    assert PeppolBisRules.text(line, "cbc:CreditedQuantity") == "1"
    refute String.starts_with?(PeppolBisRules.text(line, "cbc:LineExtensionAmount"), "-")
  end

  test "documents that cannot be sent say why" do
    [{invoice, _}, _paid, {credit, _opts}] = documents()

    assert UblInvoice.build(%{invoice | kind: "receipt"}, seller_endpoint: @seller_endpoint) ==
             {:error, :not_an_invoice}

    assert UblInvoice.build(invoice, []) == {:error, :seller_peppol_id_missing}

    assert UblInvoice.build(invoice, seller_endpoint: @seller_endpoint) ==
             {:error, :buyer_peppol_id_missing}

    assert UblInvoice.build(credit,
             seller_endpoint: @seller_endpoint,
             buyer_endpoint: @seller_endpoint
           ) == {:error, :original_missing}
  end

  test "amounts and rates are formatted as BIS expects" do
    assert UblInvoice.amount(1) == "0.01"
    assert UblInvoice.amount(123_456) == "1234.56"
    assert UblInvoice.amount(-5) == "-0.05"
    assert UblInvoice.percent(2100) == "21"
    assert UblInvoice.percent(810) == "8.1"
    assert UblInvoice.percent(550) == "5.5"
    assert UblInvoice.percent(0) == "0"
  end
end
