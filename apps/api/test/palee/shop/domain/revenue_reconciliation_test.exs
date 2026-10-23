defmodule Palee.Shop.Domain.RevenueReconciliationTest do
  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.RevenueReconciliation

  @monday ~D[2026-12-14]
  @tuesday ~D[2026-12-15]

  test "agreeing figures reconcile" do
    result =
      RevenueReconciliation.compare(
        %{@monday => 2_000},
        %{@monday => 2_000},
        %{@monday => 2_000}
      )

    assert result.ok?
    assert result.drift_cents == 0
    assert [%{day: @monday, ok?: true}] = result.days
  end

  test "a day missing from one source drifts by the whole amount" do
    result =
      RevenueReconciliation.compare(
        %{@monday => 2_000, @tuesday => 500},
        %{@monday => 2_000, @tuesday => 500},
        %{@monday => 2_000}
      )

    refute result.ok?
    assert [%{day: @tuesday, drift_cents: 500, lines_vs_payments_cents: 500}] = result.drifted
    assert result.drift_cents == 500
  end
end
