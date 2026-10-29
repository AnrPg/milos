defmodule Palee.Fiscal.Domain.PeriodClosingTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.PeriodClosing

  test "nothing to close before the first document" do
    assert PeriodClosing.due(~D[2027-02-10], nil, %{}) == []
  end

  test "every ended day closes, then months and years whose last day closed" do
    due = PeriodClosing.due(~D[2027-01-02], ~D[2026-12-30], %{})

    assert due == [
             {"day", ~D[2026-12-30], ~D[2026-12-30]},
             {"day", ~D[2026-12-31], ~D[2026-12-31]},
             {"day", ~D[2027-01-01], ~D[2027-01-01]},
             {"month", ~D[2026-12-01], ~D[2026-12-31]},
             {"year", ~D[2026-01-01], ~D[2026-12-31]}
           ]
  end

  test "closing resumes after the last closed period and is empty when up to date" do
    last = %{"day" => ~D[2027-01-01], "month" => ~D[2026-12-31], "year" => ~D[2026-12-31]}

    assert PeriodClosing.due(~D[2027-01-03], ~D[2026-12-30], last) == [
             {"day", ~D[2027-01-02], ~D[2027-01-02]}
           ]

    assert PeriodClosing.due(~D[2027-01-02], ~D[2026-12-30], last) == []
  end

  test "totals: credit notes count negative, grand totals carry over" do
    docs = [
      %{
        kind: "receipt",
        currency: "EUR",
        net_cents: 4032,
        tax_cents: 968,
        gross_cents: 5000,
        tax_breakdown: [%{rate_bp: 2400, net_cents: 4032, tax_cents: 968}]
      },
      %{
        kind: "credit_note",
        currency: "EUR",
        net_cents: 4032,
        tax_cents: 968,
        gross_cents: 5000,
        tax_breakdown: [%{"rate_bp" => 2400, "net_cents" => 4032, "tax_cents" => 968}]
      },
      %{
        kind: "invoice",
        currency: "EUR",
        net_cents: 1000,
        tax_cents: 240,
        gross_cents: 1240,
        tax_breakdown: [%{rate_bp: 2400, net_cents: 1000, tax_cents: 240}]
      }
    ]

    previous = %{
      "EUR" => %{"grand_total_cents" => 10_000, "grand_total_absolute_cents" => 20_000}
    }

    %{"EUR" => eur} = PeriodClosing.totals(docs, previous)

    assert eur["documents"] == 3
    assert eur["credit_notes"] == 1
    assert eur["gross_cents"] == 1240
    assert eur["by_rate"]["2400"] == %{"net_cents" => 1000, "tax_cents" => 240}
    assert eur["grand_total_cents"] == 11_240
    assert eur["grand_total_absolute_cents"] == 20_000 + 11_240
  end
end
