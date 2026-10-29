defmodule Palee.Infrastructure.Fiscal.MyDataXmlTest do
  @moduledoc """
  ADR-243: generated InvoicesDoc XML is valid against AADE's official XSDs
  (v2.0.1), and AADE responses are parsed safely.
  """

  use ExUnit.Case, async: true

  import Palee.FiscalTestDocuments

  alias Palee.Fiscal.Domain.MyDataInvoice
  alias Palee.Infrastructure.Fiscal.MyData.XmlCodec

  @xsd Path.expand("../../../../priv/fiscal/mydata/v2.0.1/InvoicesDoc-v2.0.1.xsd", __DIR__)

  @moduletag :tmp_dir

  defp validate!(xml, dir) do
    path = Path.join(dir, "invoices-#{System.unique_integer([:positive])}.xml")
    File.write!(path, xml)

    {output, status} =
      System.cmd("xmllint", ["--noout", "--schema", @xsd, path], stderr_to_stdout: true)

    assert status == 0, output
  end

  @tag :xmllint
  test "receipts, invoices and credit notes are valid myDATA XML", %{tmp_dir: dir} do
    greek = %{
      "name" => "ACME ΑΕ",
      "vat_number" => "094014201",
      "country_code" => "GR",
      "street" => "Λεωφ. Συγγρού",
      "building_number" => "1",
      "postal_code" => "11528",
      "city" => "Αθήνα"
    }

    german = %{
      "name" => "Box GmbH & Co <KG>",
      "vat_number" => "DE123456789",
      "country_code" => "DE",
      "postal_code" => "10119",
      "city" => "Berlin"
    }

    credit = %{corrects_document_id: Ecto.UUID.generate(), kind: "credit_note", series: "C"}

    documents = [
      {document(), []},
      {document(%{lines: [line(1, 6048, 1452, %{source_type: "product"})]}), []},
      {document(%{kind: "invoice", series: "I", buyer: greek, payment_method: "bank_transfer"}),
       []},
      {document(%{kind: "invoice", series: "I", buyer: german, currency: "EUR"}), []},
      {document(credit), [original: %{kind: "receipt", mark: "400001234567890"}]},
      {document(Map.put(credit, :buyer, greek)),
       [original: %{kind: "invoice", mark: "400001234567890"}]},
      {document(%{
         net_cents: 5000,
         tax_cents: 0,
         gross_cents: 5000,
         lines: [
           line(1, 5000, 0, %{tax_category: "exempt", rate_bp: 0, exemption_reason: "άρθρο 22"})
         ]
       }),
       [
         payment: %{
           transaction_id: "tx-1",
           tid: "16012345",
           providers_signature: %{signing_author: "viva", signature: "abc"}
         }
       ]}
    ]

    invoices =
      Enum.map(documents, fn {document, opts} ->
        {:ok, tree} = MyDataInvoice.build(document, opts)
        tree
      end)

    for invoice <- invoices, do: validate!(XmlCodec.invoices_doc([invoice]), dir)
    validate!(XmlCodec.invoices_doc(invoices), dir)
  end

  test "text is escaped" do
    xml = XmlCodec.invoices_doc([[{"issuer", [{"name", "A & B <C> \"D\""}]}]])
    assert xml =~ "A &amp; B &lt;C&gt; &quot;D&quot;"
  end

  test "parses a success and a validation error" do
    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <ResponseDoc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <response>
        <index>1</index>
        <invoiceUid>6B8A1A4F7AE9B8C0D3F2E1A0B9C8D7E6F5A4B3C2</invoiceUid>
        <invoiceMark>400001234567890</invoiceMark>
        <qrUrl>https://mydataapidev.aade.gr/TimologioQR/QRInfo?q=abc</qrUrl>
        <statusCode>Success</statusCode>
      </response>
      <response>
        <index>2</index>
        <statusCode>ValidationError</statusCode>
        <errors>
          <error><message>Το ΑΦΜ δεν είναι έγκυρο</message><code>101</code></error>
          <error><message>Second</message><code>102</code></error>
        </errors>
      </response>
    </ResponseDoc>
    """

    assert {:ok, [success, failure]} = XmlCodec.parse_response(body)
    assert success.mark == "400001234567890"
    assert success.status == "Success"
    assert success.qr_url =~ "TimologioQR"
    assert success.errors == []
    assert failure.status == "ValidationError"
    assert [%{code: "101", message: "Το ΑΦΜ δεν είναι έγκυρο"}, %{code: "102"}] = failure.errors
  end

  test "refuses entities and garbage" do
    evil = """
    <?xml version="1.0"?>
    <!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>
    <ResponseDoc><response><statusCode>&x;</statusCode></response></ResponseDoc>
    """

    assert {:error, :invalid_response} = XmlCodec.parse_response(evil)
    assert {:error, :invalid_response} = XmlCodec.parse_response("not xml")
    assert {:error, :invalid_response} = XmlCodec.parse_response(String.duplicate("a", 1_000_001))
  end
end
