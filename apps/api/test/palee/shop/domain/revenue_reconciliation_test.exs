defmodule Palee.Shop.Domain.RevenueReconciliationTest do
  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.RevenueReconciliation

  @monday {~D[2026-12-14], "EUR"}
  @tuesday {~D[2026-12-15], "EUR"}

  test "agreeing figures reconcile" do
    result =
      RevenueReconciliation.compare(
        %{@monday => 2_000},
        %{@monday => 2_000},
        %{@monday => 2_000}
      )

    assert result.ok
    assert result.drift_cents == 0
    assert [%{day: ~D[2026-12-14], currency: "EUR", ok: true}] = result.days
  end

  test "a day missing from one source drifts by the whole amount" do
    result =
      RevenueReconciliation.compare(
        %{@monday => 2_000, @tuesday => 500},
        %{@monday => 2_000, @tuesday => 500},
        %{@monday => 2_000}
      )

    refute result.ok

    assert [%{day: ~D[2026-12-15], drift_cents: 500, lines_vs_payments_cents: 500}] =
             result.drifted

    assert result.drift_cents == 500
  end

  test "a single cent is drift and currencies never net against each other" do
    result =
      RevenueReconciliation.compare(
        %{@monday => 2_000, {~D[2026-12-14], "USD"} => 100},
        %{@monday => 2_001},
        %{@monday => 2_000, {~D[2026-12-14], "USD"} => 100}
      )

    assert [%{currency: "EUR", drift_cents: 1}, %{currency: "USD", drift_cents: 100}] =
             result.drifted
  end
end
