defmodule Palee.Fiscal.Domain.MyDataInvoiceTest do
  @moduledoc "ADR-243: fiscal documents mapped to myDATA invoices."

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.MyDataInvoice

  import Palee.FiscalTestDocuments

  @seller seller()

  defp get(tree, path) do
    Enum.reduce(path, tree, fn name, node ->
      node && Enum.find_value(node, fn {key, value} -> if key == name, do: value end)
    end)
  end

  defp all(tree, name), do: for({^name, value} <- tree, do: value)

  test "a receipt for services is an ΑΠΥ 11.2 without counterpart" do
    {:ok, tree} = MyDataInvoice.build(document())

    assert get(tree, ["invoiceHeader", "invoiceType"]) == "11.2"
    assert get(tree, ["invoiceHeader", "series"]) == "R"
    assert get(tree, ["invoiceHeader", "aa"]) == "42"
    assert get(tree, ["issuer", "vatNumber"]) == "090000045"
    assert get(tree, ["issuer", "name"]) == nil
    assert get(tree, ["counterpart"]) == nil
    assert get(tree, ["paymentMethods", "paymentMethodDetails", "type"]) == "7"
    assert get(tree, ["paymentMethods", "paymentMethodDetails", "amount"]) == "75.00"

    [first, second] = all(tree, "invoiceDetails")
    assert get(first, ["netValue"]) == "48.39"
    assert get(first, ["vatCategory"]) == "1"
    assert get(second, ["vatAmount"]) == "2.91"

    assert get(first, ["incomeClassification", {:icls, "classificationType"}]) == "E3_561_003"

    assert get(first, ["incomeClassification", {:icls, "classificationCategory"}]) ==
             "category1_3"

    summary = get(tree, ["invoiceSummary"])
    assert get(summary, ["totalNetValue"]) == "60.48"
    assert get(summary, ["totalVatAmount"]) == "14.52"
    assert get(summary, ["totalGrossValue"]) == "75.00"
    assert [classification] = all(summary, "incomeClassification")
    assert get(classification, [{:icls, "amount"}]) == "60.48"
  end

  test "goods make a receipt an ΑΛΠ 11.1 with goods classification" do
    doc = document(%{lines: [line(1, 806, 194, %{source_type: "shop_order_item"})]})
    {:ok, tree} = MyDataInvoice.build(%{doc | net_cents: 806, tax_cents: 194, gross_cents: 1000})

    assert get(tree, ["invoiceHeader", "invoiceType"]) == "11.1"

    assert get(tree, ["invoiceDetails", "incomeClassification", {:icls, "classificationCategory"}]) ==
             "category1_1"
  end

  test "invoices follow the buyer's country and carry the counterpart" do
    greek = %{
      "name" => "ACME ΑΕ",
      "vat_number" => "EL094014201",
      "country_code" => "GR",
      "postal_code" => "11528",
      "city" => "Αθήνα"
    }

    german = %{
      "name" => "Box GmbH",
      "vat_number" => "DE123456789",
      "country_code" => "DE",
      "postal_code" => "10119",
      "city" => "Berlin"
    }

    swiss = %{
      "name" => "Box AG",
      "vat_number" => "CHE-123.456.788",
      "country_code" => "CH",
      "postal_code" => "8000",
      "city" => "Zürich"
    }

    {:ok, tree} = MyDataInvoice.build(document(%{kind: "invoice", series: "I", buyer: greek}))
    assert get(tree, ["invoiceHeader", "invoiceType"]) == "2.1"
    assert get(tree, ["counterpart", "vatNumber"]) == "094014201"
    assert get(tree, ["counterpart", "name"]) == nil
    assert get(tree, ["counterpart", "address", "city"]) == "Αθήνα"

    assert get(tree, ["invoiceDetails", "incomeClassification", {:icls, "classificationType"}]) ==
             "E3_561_001"

    {:ok, tree} = MyDataInvoice.build(document(%{kind: "invoice", series: "I", buyer: german}))
    assert get(tree, ["invoiceHeader", "invoiceType"]) == "2.2"
    assert get(tree, ["counterpart", "name"]) == "Box GmbH"
    assert get(tree, ["counterpart", "vatNumber"]) == "123456789"

    {:ok, tree} = MyDataInvoice.build(document(%{kind: "invoice", series: "I", buyer: swiss}))
    assert get(tree, ["invoiceHeader", "invoiceType"]) == "2.3"

    assert get(tree, ["invoiceDetails", "incomeClassification", {:icls, "classificationType"}]) ==
             "E3_561_006"
  end

  test "credit notes: 11.4 for receipts, 5.1 with the invoice's MARK" do
    credit =
      document(%{kind: "credit_note", series: "C", corrects_document_id: Ecto.UUID.generate()})

    {:ok, tree} = MyDataInvoice.build(credit, original: %{kind: "receipt", mark: nil})
    assert get(tree, ["invoiceHeader", "invoiceType"]) == "11.4"
    assert get(tree, ["invoiceHeader", "correlatedInvoices"]) == nil

    buyer = %{
      "name" => "ACME ΑΕ",
      "vat_number" => "094014201",
      "country_code" => "GR",
      "postal_code" => "11528",
      "city" => "Αθήνα"
    }

    credit = %{credit | buyer: buyer}

    assert {:error, :mydata_original_not_transmitted} =
             MyDataInvoice.build(credit, original: %{kind: "invoice", mark: nil})

    {:ok, tree} =
      MyDataInvoice.build(credit, original: %{kind: "invoice", mark: "400001234567890"})

    assert get(tree, ["invoiceHeader", "invoiceType"]) == "5.1"
    assert get(tree, ["invoiceHeader", "correlatedInvoices"]) == "400001234567890"
    assert get(tree, ["counterpart", "vatNumber"]) == "094014201"
  end

  test "VAT categories and exemptions" do
    assert MyDataInvoice.vat_category(%{tax_category: "reduced", rate_bp: 1300}) == {:ok, 2}
    assert MyDataInvoice.vat_category(%{tax_category: "super_reduced", rate_bp: 600}) == {:ok, 3}
    assert MyDataInvoice.vat_category(%{tax_category: "standard", rate_bp: 1700}) == {:ok, 4}
    assert MyDataInvoice.vat_category(%{tax_category: "exempt", rate_bp: 0}) == {:ok, 7}

    assert MyDataInvoice.vat_category(%{tax_category: "standard", rate_bp: 2000}) ==
             {:error, :mydata_unsupported_vat_rate}

    assert MyDataInvoice.exemption_category("Απαλλαγή άρθρο 22 ΚΦΠΑ", "standard") == {:ok, 7}
    assert MyDataInvoice.exemption_category("άρθ. 39α", "standard") == {:ok, 16}
    assert MyDataInvoice.exemption_category("άρθρο 2 απαλλαγή", "standard") == {:ok, 1}
    assert MyDataInvoice.exemption_category("VAT exempt, article 39", "standard") == {:ok, 15}
    assert MyDataInvoice.exemption_category("Μικρή επιχείρηση", "small_business") == {:ok, 15}

    assert MyDataInvoice.exemption_category("Χωρίς ΦΠΑ", "standard") ==
             {:error, :mydata_exemption_article_required}

    assert MyDataInvoice.exemption_category("άρθρο 99", "standard") ==
             {:error, :mydata_unknown_exemption_article}

    exempt =
      document(%{
        net_cents: 5000,
        tax_cents: 0,
        gross_cents: 5000,
        lines: [
          line(1, 5000, 0, %{tax_category: "exempt", rate_bp: 0, exemption_reason: "άρθρο 22"})
        ]
      })

    {:ok, tree} = MyDataInvoice.build(exempt)
    assert get(tree, ["invoiceDetails", "vatCategory"]) == "7"
    assert get(tree, ["invoiceDetails", "vatExemptionCategory"]) == "7"
  end

  test "payment methods and POS signature" do
    pos = %{
      transaction_id: "tx-1",
      tid: "16012345",
      providers_signature: %{signing_author: "viva", signature: "abc"}
    }

    {:ok, tree} = MyDataInvoice.build(document(), payment: pos)
    details = get(tree, ["paymentMethods", "paymentMethodDetails"])
    assert get(details, ["transactionId"]) == "tx-1"
    assert get(details, ["ProvidersSignature", "SigningAuthor"]) == "viva"

    for {method, type} <- [{"cash", "3"}, {"bank_transfer", "1"}, {nil, "5"}] do
      {:ok, tree} = MyDataInvoice.build(document(%{payment_method: method}), payment: pos)
      details = get(tree, ["paymentMethods", "paymentMethodDetails"])
      assert get(details, ["type"]) == type
      assert get(details, ["tid"]) == nil
    end
  end

  test "only Greek sellers are reported" do
    assert {:error, :mydata_seller_not_greek} =
             MyDataInvoice.build(document(%{seller: %{@seller | "country_code" => "CY"}}))
  end

  test "amounts" do
    assert MyDataInvoice.amount(0) == "0.00"
    assert MyDataInvoice.amount(5) == "0.05"
    assert MyDataInvoice.amount(123_456) == "1234.56"
  end
end
