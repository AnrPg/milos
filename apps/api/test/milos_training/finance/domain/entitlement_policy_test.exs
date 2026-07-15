defmodule MilosTraining.Finance.Domain.EntitlementPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.EntitlementPolicy

  test "allows unmanaged, active, and grace access during finance rollout" do
    assert :ok = EntitlementPolicy.authorize(nil, :class_booking)
    assert :ok = EntitlementPolicy.authorize(%{status: "active"}, :class_booking)
    assert :ok = EntitlementPolicy.authorize(%{status: "grace"}, :workout_execution)
  end

  test "rejects blocked and inactive managed memberships" do
    assert {:error, :finance_entitlement_blocked} =
             EntitlementPolicy.authorize(%{status: "blocked"}, :class_booking)

    assert {:error, :finance_entitlement_inactive} =
             EntitlementPolicy.authorize(%{status: "inactive"}, :workout_execution)
  end
end
