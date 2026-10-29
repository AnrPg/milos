defmodule Palee.Fiscal.Domain.TaxEngineTest do
  @moduledoc "ADR-244/245 pure rules: IBANs, tax categories, sale lines and the US rate table."

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{Iban, SaleLines, SalesTaxRateTable, TaxCategories, VatRates}

  describe "Iban" do
    test "validates length and mod 97, normalises and formats" do
      assert Iban.valid?("CH5604835012345678009")
      assert Iban.valid?("DE89370400440532013000")
      assert Iban.valid?("GR1601101250000000012300695")
      refute Iban.valid?("DE89370400440532013001")
      refute Iban.valid?("DE8937040044053201300")

      assert Iban.normalize(" ch56 0483 5012 3456 7800 9 ") == "CH5604835012345678009"
      assert Iban.format("CH5604835012345678009") == "CH56 0483 5012 3456 7800 9"
      assert Iban.validate("CH56 0483 5012 3456 7800 9") == {:ok, "CH5604835012345678009"}
      assert {:error, _reason} = Iban.validate("CH00 0000")
    end

    test "a QR-IBAN is a Swiss/Liechtenstein IBAN with an IID from 30000 to 31999" do
      assert Iban.qr_iban?("CH4431999123000889012")
      refute Iban.qr_iban?("CH5604835012345678009")
      refute Iban.qr_iban?("DE89370400440532013000")
    end
  end

  describe "TaxCategories" do
    test "checks the category against the seller's country and requires exemption reasons" do
      assert :ok = TaxCategories.check("GR", "reduced", nil)
      assert :ok = TaxCategories.check(nil, "sales_tax", nil)
      assert :ok = TaxCategories.check("US", "sales_tax", nil)

      assert {:error, {:invalid_fields, %{tax_category: :not_available_in_country}}} =
               TaxCategories.check("US", "reduced", nil)

      assert {:error, {:invalid_fields, %{tax_category: :invalid}}} =
               TaxCategories.check("GR", "luxury", nil)

      assert {:error, {:invalid_fields, %{exemption_reason: :required}}} =
               TaxCategories.check("GR", "exempt", "  ")

      assert {:error, {:invalid_fields, %{exemption_reason: :too_long}}} =
               TaxCategories.check("GR", "exempt", String.duplicate("x", 301))
    end

    test "defaults, inheritance and small-business mentions" do
      assert TaxCategories.default("US") == "sales_tax"
      assert TaxCategories.default("DE") == "standard"
      assert TaxCategories.effective(nil, "reduced", "GR") == "reduced"
      assert TaxCategories.effective("zero", "reduced", "GR") == "zero"
      assert TaxCategories.effective(" ", nil, "US") == "sales_tax"
      assert TaxCategories.small_business_reason("DE") =~ "§ 19 UStG"
      assert TaxCategories.small_business_reason("FR") == "TVA non applicable, art. 293 B du CGI"
    end
  end

  describe "SaleLines" do
    @seller %{country_code: "GR", vat_scheme: "standard"}

    test "turns a package and a variant into issue request lines" do
      package = %{
        id: "p1",
        name: "Unlimited",
        base_price_cents: 6_000,
        tax_category: nil,
        exemption_reason: nil
      }

      product = %{id: "s1", title: "Protein bar", tax_category: "reduced", exemption_reason: nil}
      variant = %{id: "v1", title: "Chocolate", price_cents: 300, tax_category: nil}

      assert {:ok, [membership, bar]} =
               SaleLines.lines(
                 [
                   SaleLines.package_item(package),
                   SaleLines.variant_item(product, variant, quantity: 2, discount_cents: 50)
                 ],
                 @seller
               )

      assert membership == %{
               description: "Unlimited",
               quantity: 1,
               unit_price_cents: 6_000,
               discount_cents: 0,
               tax_category: "standard",
               exemption_reason: nil,
               rate_bp: nil,
               source_type: "membership_package",
               source_id: "p1"
             }

      assert %{
               description: "Protein bar – Chocolate",
               quantity: 2,
               discount_cents: 50,
               tax_category: "reduced",
               source_type: "shop_variant",
               source_id: "v1"
             } = bar
    end

    test "a small business prints every line exempt with its legal mention" do
      assert {:ok, [line]} =
               SaleLines.lines(
                 [%{description: "Drop-in", unit_price_cents: 1_500, tax_category: "reduced"}],
                 %{"country_code" => "DE", "vat_scheme" => "small_business"}
               )

      assert line.tax_category == "exempt"
      assert line.exemption_reason =~ "§ 19 UStG"
    end

    test "errors carry the item's index" do
      assert {:error, {:invalid_sale_line, 1, :exemption_reason_required}} =
               SaleLines.lines(
                 [
                   %{description: "A", unit_price_cents: 100},
                   %{description: "B", unit_price_cents: 100, tax_category: "exempt"}
                 ],
                 @seller
               )

      assert {:error, {:invalid_sale_line, 0, :unknown_tax_category}} =
               SaleLines.lines(
                 [%{description: "A", unit_price_cents: 100, tax_category: "sales_tax"}],
                 @seller
               )

      assert {:error, {:invalid_sale_line, 0, :discount_exceeds_amount}} =
               SaleLines.lines(
                 [%{description: "A", unit_price_cents: 100, discount_cents: 101}],
                 @seller
               )

      assert {:error, {:invalid_sale_line, 0, :invalid_quantity}} =
               SaleLines.lines([%{description: "A", unit_price_cents: 1, quantity: 0}], @seller)

      assert {:error, {:invalid_sale_line, 0, :missing_description}} =
               SaleLines.lines([%{description: " ", unit_price_cents: 1}], @seller)
    end

    test "US sales tax lines keep the calculator's rate" do
      assert {:ok, [%{tax_category: "sales_tax", rate_bp: 887}]} =
               SaleLines.lines(
                 [%{description: "Membership", unit_price_cents: 9_900, rate_bp: 887}],
                 %{country_code: "US"}
               )
    end

    test "a Finance invoice finds each line's category by source, package, charge or default" do
      invoice = %{id: "inv-1", currency: "EUR"}

      lines = [
        %{id: "l1", description: "Unlimited", quantity: 1, unit_amount_cents: 6_000,
          package_code_snapshot: "UNL"},
        %{id: "l2", description: "Water", quantity: 3, unit_amount_cents: 100,
          source_id: "order-line-9"},
        %{id: "l3", description: "Workshop", quantity: 1, unit_amount_cents: 2_000,
          charge_category: "event"},
        %{id: "l4", description: "Other", quantity: 1, unit_amount_cents: 500}
      ]

      taxes = %{
        packages: %{"UNL" => %{tax_category: "standard"}},
        sources: %{"order-line-9" => %{tax_category: "reduced"}},
        charges: %{"event" => %{tax_category: "exempt", exemption_reason: "Art. 22 VAT code"}},
        default: %{tax_category: "super_reduced"}
      }

      assert {:ok,
              %{
                currency: "EUR",
                prices_include_tax: true,
                source_type: "finance_invoice",
                source_id: "inv-1",
                lines: lines
              }} = SaleLines.finance_invoice(invoice, lines, taxes, @seller)

      assert Enum.map(lines, & &1.tax_category) == ~w(standard reduced exempt super_reduced)
      assert Enum.at(lines, 2).exemption_reason == "Art. 22 VAT code"
      assert Enum.all?(lines, &(&1.source_type == "finance_invoice_line"))
    end

    test "every builder output is accepted by the country's categories" do
      for country <- ~w(GR DE FR CH), category <- VatRates.categories(country) do
        reason = if category == "exempt", do: "Exempt"

        assert {:ok, [%{tax_category: ^category}]} =
                 SaleLines.lines(
                   [
                     %{
                       description: "X",
                       unit_price_cents: 100,
                       tax_category: category,
                       exemption_reason: reason
                     }
                   ],
                   %{country_code: country}
                 )
      end
    end
  end

  describe "SalesTaxRateTable" do
    test "normalises rows and finds the ZIP rate before the state rate" do
      assert {:ok, rows} =
               SalesTaxRateTable.normalize([
                 %{"state" => "ny", "zip" => "10001", "rate_bp" => 887, "label" => "NYC"},
                 %{"state" => "NY", "rate_bp" => 400}
               ])

      assert [%{state: "NY", zip: nil}, %{state: "NY", zip: "10001"}] = rows
      assert SalesTaxRateTable.lookup(rows, "NY", "10001-1234") == {:ok, 887}
      assert SalesTaxRateTable.lookup(rows, "ny", "12207") == {:ok, 400}
      assert SalesTaxRateTable.lookup(rows, "CA", "90001") == {:error, :sales_tax_rate_missing}
    end

    test "reports errors per row and duplicates" do
      assert {:error, {:invalid_fields, errors}} =
               SalesTaxRateTable.normalize([
                 %{"state" => "XX", "rate_bp" => 100},
                 %{"state" => "CA", "zip" => "9000", "rate_bp" => 100},
                 %{"state" => "CA", "rate_bp" => -1},
                 %{"state" => "TX", "rate_bp" => 625},
                 %{"state" => "TX", "rate_bp" => 600}
               ])

      assert errors["rates.0.state"] == :invalid
      assert errors["rates.1.zip"] == :invalid
      assert errors["rates.2.rate_bp"] == :invalid
      assert errors["rates.TX.state"] == :duplicate
    end
  end
end
