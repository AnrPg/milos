defmodule Palee.Finance.Domain.PackageRequestPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.PackageRequestPolicy, as: Policy

  test "a request is held 14 days, counted in the box's days" do
    assert Policy.hold_days() == 14
    assert Policy.hold_until(~D[2026-10-31]) == ~D[2026-11-14]
  end

  test "it is open through its last day and closed from the day after" do
    request = %{status: "pending", hold_until: ~D[2026-11-14]}

    assert Policy.open?(request, ~D[2026-10-31])
    assert Policy.open?(request, ~D[2026-11-14])
    refute Policy.open?(request, ~D[2026-11-15])
    refute Policy.open?(%{request | status: "activated"}, ~D[2026-10-31])
  end

  test "days left never go below zero" do
    request = %{hold_until: ~D[2026-11-14]}
    assert Policy.days_left(request, ~D[2026-10-31]) == 14
    assert Policy.days_left(request, ~D[2026-11-20]) == 0
  end

  test "only active, paid packages sold on their own can be asked for" do
    package = %{active: true, base_price_cents: 7_000, package_type: "membership"}

    assert Policy.requestable?(package)
    refute Policy.requestable?(%{package | active: false})
    refute Policy.requestable?(%{package | base_price_cents: 0})
    refute Policy.requestable?(%{package | package_type: "add_on"})
    refute Policy.requestable?(%{package | package_type: "corporate"})
    refute Policy.requestable?(nil)
  end
end
