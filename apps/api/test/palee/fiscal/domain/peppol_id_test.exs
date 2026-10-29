defmodule Palee.Fiscal.Domain.PeppolIdTest do
  @moduledoc "ADR-250: Peppol participant identifiers."

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.PeppolId

  test "parses and normalises identifiers, checking Belgian enterprise numbers" do
    assert PeppolId.parse("0208:0403.170.701") ==
             {:ok, %{scheme: "0208", identifier: "0403170701"}}

    assert PeppolId.parse("0208:BE0403170701") ==
             {:ok, %{scheme: "0208", identifier: "0403170701"}}

    assert PeppolId.parse("9925:be0403170701") ==
             {:ok, %{scheme: "9925", identifier: "BE0403170701"}}

    assert PeppolId.parse("0088:5790000435968") ==
             {:ok, %{scheme: "0088", identifier: "5790000435968"}}

    assert PeppolId.parse("0208:0403170702") == {:error, :invalid_peppol_id}
    assert PeppolId.parse("9999:123") == {:error, :invalid_peppol_id}
    assert PeppolId.parse("0208") == {:error, :invalid_peppol_id}
    assert PeppolId.parse(nil) == {:error, :invalid_peppol_id}
    assert PeppolId.format(%{scheme: "0208", identifier: "0403170701"}) == "0208:0403170701"
  end

  test "a buyer's identifier is its own or derived from a Belgian VAT number" do
    assert PeppolId.for_party(%{peppol_id: "0088:5790000435968", vat_number: "BE0403170701"}) ==
             {:ok, %{scheme: "0088", identifier: "5790000435968"}}

    assert PeppolId.for_party(%{vat_number: "BE 0202.239.951"}) ==
             {:ok, %{scheme: "0208", identifier: "0202239951"}}

    assert PeppolId.for_party(%{tax_id: "202239951", country_code: "BE"}) ==
             {:ok, %{scheme: "0208", identifier: "0202239951"}}

    assert PeppolId.for_party(%{vat_number: "DE123456789"}) == {:error, :buyer_peppol_id_missing}
    assert PeppolId.for_party(nil) == {:error, :buyer_peppol_id_missing}
  end
end
