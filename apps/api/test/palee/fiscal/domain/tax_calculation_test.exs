defmodule Palee.Fiscal.Domain.TaxCalculationTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.TaxCalculation

  defp line(unit, rate, quantity \\ 1, discount \\ 0),
    do: %{
      quantity: quantity,
      unit_price_cents: unit,
      discount_cents: discount,
      rate_bp: rate,
      tax_category: "standard"
    }

  test "gross prices: tax is extracted per rate group, half up" do
    # 50.00 at 24 %: 5000 × 24 / 124 = 967.74 → 968
    assert {:ok, result} = TaxCalculation.compute([line(5000, 2400)], true)
    assert %{net_cents: 4032, tax_cents: 968, gross_cents: 5000} = result

    assert [%{net_cents: 4032, tax_cents: 968, gross_cents: 5000, amount_cents: 5000}] =
             result.lines
  end

  test "net prices: tax is added per group, not per line" do
    # three lines of 0.05 at 24 %: per line 0.012 → 0.01 each = 0.03; per group 0.036 → 0.04
    lines = for _ <- 1..3, do: line(5, 2400)
    assert {:ok, result} = TaxCalculation.compute(lines, false)
    assert result.tax_cents == 4
    assert result.net_cents == 15
    assert result.lines |> Enum.map(& &1.tax_cents) |> Enum.sum() == 4
  end

  test "groups are separate per rate and ordered by rate" do
    assert {:ok, result} = TaxCalculation.compute([line(1000, 600), line(2000, 2400)], true)
    assert [%{rate_bp: 2400}, %{rate_bp: 600}] = result.groups
    assert result.gross_cents == 3000
  end

  test "discounts and quantities" do
    assert {:ok, %{lines: [l]}} = TaxCalculation.compute([line(1000, 2400, 3, 500)], true)
    assert l.amount_cents == 2500

    assert {:error, :discount_exceeds_amount} =
             TaxCalculation.compute([line(100, 2400, 1, 200)], true)

    assert {:error, :invalid_quantity} = TaxCalculation.compute([line(100, 2400, 0)], true)
    assert {:error, :invalid_tax_rate} = TaxCalculation.compute([line(100, 10_000)], true)
    assert {:error, :no_lines} = TaxCalculation.compute([], true)
  end

  test "allocate shares by largest remainder" do
    assert TaxCalculation.allocate(10, [1, 1, 1]) == [4, 3, 3]
    assert TaxCalculation.allocate(5, [0, 0]) == [5, 0]
    assert TaxCalculation.allocate(0, [3, 4]) == [0, 0]
  end

  test "lines, groups and totals always add up to the cent (500 random documents)" do
    :rand.seed(:exsss, {1, 2, 3})
    rates = [0, 210, 550, 600, 810, 1300, 2000, 2400]

    for _ <- 1..500 do
      input =
        for _ <- 1..Enum.random(1..12),
            do: line(Enum.random(0..50_000), Enum.random(rates), Enum.random(1..5))

      gross? = Enum.random([true, false])
      {:ok, result} = TaxCalculation.compute(input, gross?)

      assert result.gross_cents == result.net_cents + result.tax_cents
      assert Enum.sum(Enum.map(result.lines, & &1.gross_cents)) == result.gross_cents
      assert Enum.sum(Enum.map(result.lines, & &1.tax_cents)) == result.tax_cents
      assert Enum.sum(Enum.map(result.groups, & &1.tax_cents)) == result.tax_cents
      amounts = Enum.sum(Enum.map(result.lines, & &1.amount_cents))

      if gross?,
        do: assert(result.gross_cents == amounts),
        else: assert(result.net_cents == amounts)
    end
  end
end
