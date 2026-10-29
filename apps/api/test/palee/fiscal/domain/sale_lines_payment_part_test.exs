defmodule Palee.Fiscal.Domain.SaleLinesPaymentPartTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.SaleLines

  defp line(category, rate_bp, gross, reason \\ nil) do
    %{
      description: "#{category} #{rate_bp}",
      quantity: 1,
      unit_price_cents: gross,
      discount_cents: 0,
      tax_category: category,
      exemption_reason: reason,
      rate_bp: rate_bp,
      source_type: "finance_invoice_line",
      source_id: Ecto.UUID.generate()
    }
  end

  test "the full amount keeps the invoice's own lines" do
    lines = [line("standard", 2_400, 5_000), line("reduced", 1_300, 1_000)]
    assert SaleLines.payment_part(lines, 6_000, "Part") == {:ok, lines}
  end

  test "a part payment splits by tax group in proportion, to the cent" do
    lines = [
      line("standard", 2_400, 5_000),
      line("standard", 2_400, 1_000),
      line("exempt", 0, 3_001, "art_22")
    ]

    assert {:ok, parts} = SaleLines.payment_part(lines, 1_000, "Δόση")
    assert Enum.sum(Enum.map(parts, & &1.unit_price_cents)) == 1_000
    assert length(parts) == 2

    standard = Enum.find(parts, &(&1.tax_category == "standard"))
    exempt = Enum.find(parts, &(&1.tax_category == "exempt"))

    # 1000 * 6000 / 9001 = 666.59…, 1000 * 3001 / 9001 = 333.40…
    assert standard.unit_price_cents == 667
    assert exempt.unit_price_cents == 333
    assert exempt.exemption_reason == "art_22"
    assert Enum.all?(parts, &(&1.quantity == 1 and &1.description == "Δόση"))
  end

  test "amounts outside the invoice are refused" do
    lines = [line("standard", 2_400, 1_000)]
    assert SaleLines.payment_part(lines, 0, "x") == {:error, :invalid_amount}
    assert SaleLines.payment_part(lines, 1_001, "x") == {:error, :invalid_amount}
  end
end
