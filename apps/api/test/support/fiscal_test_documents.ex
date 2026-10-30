defmodule Palee.FiscalTestDocuments do
  @moduledoc "Fiscal documents shaped as the store returns them, for myDATA mapping tests (ADR-243)."

  def seller do
    %{
      "legal_name" => "CrossFit Αθήνα ΙΚΕ",
      "country_code" => "GR",
      "tax_id" => "090000045",
      "vat_scheme" => "standard",
      "postal_code" => "10563",
      "city" => "Αθήνα",
      "branch_code" => 0
    }
  end

  def document(extra \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        kind: "receipt",
        series: "R",
        sequence: 42,
        issue_date: ~D[2027-02-01],
        currency: "EUR",
        seller: seller(),
        buyer: nil,
        payment_method: "card",
        net_cents: 6048,
        tax_cents: 1452,
        gross_cents: 7500,
        corrects_document_id: nil,
        lines: [line(1, 4839, 1161, %{}), line(2, 1209, 291, %{})]
      },
      extra
    )
  end

  def line(position, net, tax, extra \\ %{}) do
    Map.merge(
      %{
        position: position,
        net_cents: net,
        tax_cents: tax,
        tax_category: "standard",
        rate_bp: 2400,
        exemption_reason: nil,
        source_type: nil
      },
      extra
    )
  end
end
