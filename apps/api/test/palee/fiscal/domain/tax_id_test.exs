defmodule Palee.Fiscal.Domain.TaxIdTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.TaxId

  test "normalises spaces, dots, dashes and case" do
    assert TaxId.normalize(" che-116.281.710 ") == "CHE116281710"
    assert TaxId.normalize("  ") == nil
  end

  describe "Greece" do
    test "ΑΦΜ check digit" do
      assert {:ok, "090000045"} = TaxId.validate("GR", :tax_id, "090000045")
      assert {:error, :check_digit} = TaxId.validate("GR", :tax_id, "090000046")
      assert {:error, :check_digit} = TaxId.validate("GR", :tax_id, "000000000")
      assert {:error, :format} = TaxId.validate("GR", :tax_id, "12345")
    end

    test "VAT number gets the EL prefix, GR is accepted as an alias" do
      assert {:ok, "EL090000045"} = TaxId.validate("GR", :vat_number, "090000045")
      assert {:ok, "EL090000045"} = TaxId.validate("GR", :vat_number, "EL 090000045")
      assert {:ok, "EL090000045"} = TaxId.validate("GR", :vat_number, "GR090000045")
    end
  end

  test "German VAT number, ISO 7064 MOD 11,10" do
    assert {:ok, "DE136695976"} = TaxId.validate("DE", :vat_number, "DE 136 695 976")
    assert {:error, :check_digit} = TaxId.validate("DE", :vat_number, "DE136695977")
  end

  test "Austrian UID" do
    assert {:ok, "ATU13585627"} = TaxId.validate("AT", :vat_number, "ATU13585627")
    assert {:error, :check_digit} = TaxId.validate("AT", :vat_number, "ATU13585628")
  end

  test "Swiss UID and VAT number" do
    assert {:ok, "CHE116281710"} = TaxId.validate("CH", :registration_number, "CHE-116.281.710")
    assert {:ok, "CHE116281710MWST"} = TaxId.validate("CH", :vat_number, "CHE-116.281.710 MWST")
    assert {:error, :check_digit} = TaxId.validate("CH", :vat_number, "CHE-116.281.711")
  end

  test "Luxembourg VAT number" do
    assert {:ok, "LU15027442"} = TaxId.validate("LU", :vat_number, "LU15027442")
    assert {:error, :check_digit} = TaxId.validate("LU", :vat_number, "LU15027443")
  end

  test "French SIREN (Luhn) and VAT key" do
    assert {:ok, "732829320"} = TaxId.validate("FR", :registration_number, "732 829 320")
    assert {:error, :check_digit} = TaxId.validate("FR", :registration_number, "732829321")

    key =
      rem(12 + 3 * rem(732_829_320, 97), 97) |> Integer.to_string() |> String.pad_leading(2, "0")

    assert {:ok, _} = TaxId.validate("FR", :vat_number, "FR" <> key <> "732829320")

    wrong =
      rem(String.to_integer(key) + 1, 97) |> Integer.to_string() |> String.pad_leading(2, "0")

    assert {:error, :check_digit} =
             TaxId.validate("FR", :vat_number, "FR" <> wrong <> "732829320")
  end

  test "Belgian enterprise number" do
    body = "04031707"

    check =
      (97 - rem(String.to_integer(body), 97)) |> Integer.to_string() |> String.pad_leading(2, "0")

    assert {:ok, number} = TaxId.validate("BE", :tax_id, body <> check)
    assert number == body <> check
    assert {:ok, "BE" <> ^number} = TaxId.validate("BE", :vat_number, "BE " <> number)
    assert {:error, :check_digit} = TaxId.validate("BE", :tax_id, body <> "00")
  end

  test "US has no VAT number; unsupported countries are refused" do
    assert {:error, :not_applicable} = TaxId.validate("US", :vat_number, "123")
    assert {:ok, "123456789"} = TaxId.validate("US", :tax_id, "12-3456789")
    assert {:error, :unsupported_country} = TaxId.validate("XX", :tax_id, "1")
    assert {:error, :blank} = TaxId.validate("GR", :tax_id, " ")
  end
end
