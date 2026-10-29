defmodule Palee.Fiscal.Domain.FiscalDocumentPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{BusinessIdentityPolicy, FiscalDocumentPolicy}

  @greek %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    vat_scheme: "standard",
    street: "Ερμού",
    postal_code: "10563",
    city: "Αθήνα",
    branch_code: 0
  }

  defp receipt(lines, extra \\ %{}),
    do: Map.merge(%{kind: "receipt", issue_date: ~D[2027-02-01], lines: lines}, extra)

  defp membership(price \\ 6000),
    do: %{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: price}

  test "a Greek retail receipt at 24 % with the seller snapshot" do
    assert {:ok, doc} = FiscalDocumentPolicy.build(@greek, receipt([membership()]))
    assert doc.currency == "EUR"
    assert doc.language == "el"
    assert doc.gross_cents == 6000
    assert doc.tax_cents == 1161
    assert [%{position: 1, rate_bp: 2400, tax_category: "standard"}] = doc.lines
    assert doc.seller.tax_id == "090000045"
    refute Map.has_key?(doc.seller, :phone)
  end

  test "an incomplete identity cannot issue" do
    assert {:error, :fiscal_identity_incomplete} =
             FiscalDocumentPolicy.build(Map.delete(@greek, :tax_office), receipt([membership()]))
  end

  test "an invoice needs the buyer's address, and in Greece the buyer's tax id" do
    buyer = %{
      name: "Εταιρεία ΑΕ",
      street: "Σταδίου 1",
      postal_code: "10562",
      city: "Αθήνα",
      country_code: "GR"
    }

    assert {:error, :buyer_required} =
             FiscalDocumentPolicy.build(@greek, receipt([membership()], %{kind: "invoice"}))

    assert {:error, :buyer_tax_id_required} =
             FiscalDocumentPolicy.build(
               @greek,
               receipt([membership()], %{kind: "invoice", buyer: buyer})
             )

    assert {:ok, %{kind: "invoice"}} =
             FiscalDocumentPolicy.build(
               @greek,
               receipt([membership()], %{
                 kind: "invoice",
                 buyer: Map.put(buyer, :vat_number, "EL090000045")
               })
             )
  end

  test "a business outside VAT issues only exempt lines with a reason" do
    small = %{@greek | vat_scheme: "small_business"}

    assert {:error, :business_not_vat_registered} =
             FiscalDocumentPolicy.build(small, receipt([membership()]))

    exempt = Map.merge(membership(), %{tax_category: "exempt"})

    assert {:error, :exemption_reason_required} =
             FiscalDocumentPolicy.build(small, receipt([exempt]))

    assert {:ok, %{tax_cents: 0}} =
             FiscalDocumentPolicy.build(
               small,
               receipt([Map.put(exempt, :exemption_reason, "Άρθρο 39")])
             )
  end

  test "unknown categories and US sales tax need a rate" do
    assert {:error, :unknown_tax_category} =
             FiscalDocumentPolicy.build(
               @greek,
               receipt([Map.put(membership(), :tax_category, "special")])
             )

    us = %{
      legal_name: "Box LLC",
      country_code: "US",
      street: "1 Main",
      postal_code: "10001",
      city: "NY",
      region: "NY",
      vat_scheme: "standard",
      branch_code: 0
    }

    line = Map.put(membership(), :tax_category, "sales_tax")
    assert {:error, :invalid_tax_rate} = FiscalDocumentPolicy.build(us, receipt([line]))

    assert {:ok, %{currency: "USD", tax_cents: 533}} =
             FiscalDocumentPolicy.build(
               us,
               receipt([Map.put(line, :rate_bp, 888)], %{prices_include_tax: false})
             )
  end

  describe "credit notes" do
    setup do
      {:ok, doc} =
        FiscalDocumentPolicy.build(
          @greek,
          receipt([Map.put(membership(1000), :quantity, 3), membership(500)])
        )

      %{original: Map.merge(doc, %{id: Ecto.UUID.generate()})}
    end

    test "a full credit note mirrors the original", %{original: original} do
      assert {:ok, note} = FiscalDocumentPolicy.credit_note(original, %{}, :all, ~D[2027-02-02])
      assert note.kind == "credit_note"
      assert note.corrects_document_id == original.id

      assert {note.net_cents, note.tax_cents, note.gross_cents} ==
               {original.net_cents, original.tax_cents, original.gross_cents}

      assert Enum.map(note.lines, & &1.corrects_position) == [1, 2]
    end

    test "partial credit notes never exceed the original", %{original: original} do
      assert {:ok, first} =
               FiscalDocumentPolicy.credit_note(
                 original,
                 %{},
                 [%{position: 1, quantity: 2}],
                 ~D[2027-02-02]
               )

      assert [%{quantity: 2, amount_cents: 2000}] = first.lines

      credited = %{1 => %{quantity: 2, amount_cents: 2000}}

      assert {:error, :credit_exceeds_document} =
               FiscalDocumentPolicy.credit_note(
                 original,
                 credited,
                 [%{position: 1, quantity: 2}],
                 ~D[2027-02-02]
               )

      assert {:ok, rest} =
               FiscalDocumentPolicy.credit_note(original, credited, :all, ~D[2027-02-02])

      assert Enum.map(rest.lines, &{&1.corrects_position, &1.quantity}) == [{1, 1}, {2, 1}]

      all = %{1 => %{quantity: 3, amount_cents: 3000}, 2 => %{quantity: 1, amount_cents: 500}}

      assert {:error, :already_credited} =
               FiscalDocumentPolicy.credit_note(original, all, :all, ~D[2027-02-02])

      assert {:error, :unknown_line} =
               FiscalDocumentPolicy.credit_note(
                 original,
                 %{},
                 [%{position: 9, quantity: 1}],
                 ~D[2027-02-02]
               )
    end

    test "a part refund credits an amount over what is left, in proportion",
         %{original: original} do
      assert {:ok, part} =
               FiscalDocumentPolicy.credit_note(
                 original,
                 %{},
                 %{amount_cents: 700},
                 ~D[2027-02-02]
               )

      assert part.gross_cents == 700

      assert Enum.map(part.lines, &{&1.corrects_position, &1.quantity, &1.amount_cents}) ==
               [{1, 1, 600}, {2, 1, 100}]

      credited = %{1 => %{quantity: 1, amount_cents: 600}, 2 => %{quantity: 1, amount_cents: 100}}

      assert {:error, :credit_exceeds_document} =
               FiscalDocumentPolicy.credit_note(
                 original,
                 credited,
                 %{amount_cents: 2_801},
                 ~D[2027-02-02]
               )

      assert {:error, :invalid_credit_amount} =
               FiscalDocumentPolicy.credit_note(original, %{}, %{amount_cents: 0}, ~D[2027-02-02])

      # What is left is credited in full, whatever the quantities say.
      assert {:ok, rest} =
               FiscalDocumentPolicy.credit_note(original, credited, :all, ~D[2027-02-02])

      assert rest.gross_cents == 2_800

      assert Enum.map(rest.lines, &{&1.corrects_position, &1.amount_cents}) == [
               {1, 2400},
               {2, 400}
             ]
    end

    test "a credit note cannot be credited", %{original: original} do
      {:ok, note} = FiscalDocumentPolicy.credit_note(original, %{}, :all, ~D[2027-02-02])

      assert {:error, :not_creditable} =
               FiscalDocumentPolicy.credit_note(note, %{}, :all, ~D[2027-02-02])
    end
  end

  describe "identity" do
    test "validates tax ids by country and normalises them" do
      assert {:ok, attrs} =
               BusinessIdentityPolicy.validate(%{}, %{
                 country_code: "gr",
                 tax_id: "090 000 045",
                 vat_number: "090000045"
               })

      assert attrs.country_code == "GR"
      assert attrs.vat_number == "EL090000045"
      assert attrs.currency == "EUR"

      assert {:error, {:invalid_fields, %{tax_id: :check_digit}}} =
               BusinessIdentityPolicy.validate(%{}, %{country_code: "GR", tax_id: "090000046"})

      assert {:error, {:invalid_fields, errors}} =
               BusinessIdentityPolicy.validate(%{}, %{country_code: "XX", tax_id: "090000046"})

      assert errors == %{country_code: :unsupported_country}
    end

    test "Swiss businesses get CHF and partial updates keep earlier fields" do
      {:ok, ch} =
        BusinessIdentityPolicy.validate(%{}, %{country_code: "CH", legal_name: "Box AG"})

      assert ch.currency == "CHF"
      {:ok, updated} = BusinessIdentityPolicy.validate(ch, %{city: "Zürich"})
      assert updated.legal_name == "Box AG"
      assert BusinessIdentityPolicy.changed_fields(ch, updated) == [:city]
    end

    test "document language must be one of the country's" do
      assert {:error, {:invalid_fields, %{document_language: :invalid}}} =
               BusinessIdentityPolicy.validate(%{}, %{country_code: "GB", document_language: "el"})
    end
  end
end
