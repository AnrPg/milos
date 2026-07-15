defmodule MilosTraining.Finance.Domain.MembershipLifecycleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.MembershipLifecycle

  test "derives expired and expiring statuses from expiration dates" do
    today = ~D[2026-06-11]

    assert MembershipLifecycle.derive_status("active", nil, ~D[2026-06-10], today) == "expired"
    assert MembershipLifecycle.derive_status("active", nil, ~D[2026-06-18], today) == "expiring"
    assert MembershipLifecycle.derive_status("active", nil, ~D[2026-08-01], today) == "active"
  end

  test "preserves manual paused and cancelled statuses" do
    today = ~D[2026-06-11]

    assert MembershipLifecycle.derive_status("cancelled", nil, ~D[2026-06-10], today) ==
             "cancelled"

    assert MembershipLifecycle.derive_status("paused", nil, ~D[2026-06-10], today) == "paused"
  end

  test "accepts browser date strings" do
    assert MembershipLifecycle.derive_status("active", nil, "2026-06-10", ~D[2026-06-11]) ==
             "expired"
  end
end
