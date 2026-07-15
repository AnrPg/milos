defmodule MilosTraining.Finance.Domain.EntitlementPlanTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.{AllowancePeriod, EntitlementPlan, EntitlementPolicy}

  @plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person", "personal_programming"],
    "capabilities" => ["book_classes", "execute_assigned_workouts"],
    "allowances" => %{
      "class_visits" => %{"limit" => 3, "period" => "calendar_week"},
      "coaching_touchpoints" => %{"limit" => "unlimited", "period" => "calendar_month"}
    }
  }

  test "normalizes a versioned plan into atoms without creating arbitrary atoms" do
    assert {:ok, plan} = EntitlementPlan.parse(@plan)
    assert plan.version == 1
    assert plan.channels == MapSet.new([:in_person, :personal_programming])
    assert plan.capabilities == MapSet.new([:book_classes, :execute_assigned_workouts])
    assert plan.allowances.class_visits.limit == 3
    assert plan.allowances.coaching_touchpoints.limit == :unlimited
  end

  test "rejects unknown capabilities and malformed allowances" do
    assert {:error, {:unknown_capability, "teleport"}} =
             EntitlementPlan.parse(put_in(@plan["capabilities"], ["teleport"]))

    assert {:error, {:invalid_allowance_limit, "class_visits"}} =
             EntitlementPlan.parse(put_in(@plan["allowances"]["class_visits"]["limit"], -1))
  end

  test "calculates deterministic calendar and subscription periods" do
    assert {~D[2026-07-13], ~D[2026-07-19]} =
             AllowancePeriod.bounds(:calendar_week, ~D[2026-07-15], %{})

    assert {~D[2026-07-01], ~D[2026-07-31]} =
             AllowancePeriod.bounds(:calendar_month, ~D[2026-07-15], %{})

    assert {~D[2026-07-10], ~D[2026-08-09]} =
             AllowancePeriod.bounds(:subscription_period, ~D[2026-07-15], %{
               starts_on: ~D[2026-07-10],
               ends_on: ~D[2026-08-09]
             })
  end

  test "requires both channel and capability and reports quota exhaustion" do
    entitlement = %{status: "active", plan: @plan}

    request = %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      limit: 3,
      committed: 2,
      quantity: 1
    }

    assert {:ok, decision} = EntitlementPolicy.authorize(entitlement, request, mode: :enforce_all)
    assert decision.remaining == 0

    assert {:error, :finance_allowance_exhausted, %{limit: 3, committed: 3}} =
             EntitlementPolicy.authorize(
               entitlement,
               %{request | committed: 3},
               mode: :enforce_all
             )

    assert {:error, :finance_channel_not_included} =
             EntitlementPolicy.authorize(
               entitlement,
               %{request | channel: :workout_library},
               mode: :enforce_all
             )
  end

  test "rollout mode controls missing profiles and admins bypass customer finance" do
    request = %{channel: :in_person, capability: :book_classes}

    assert {:ok, %{observed?: true}} = EntitlementPolicy.authorize(nil, request, mode: :observe)
    assert :ok = EntitlementPolicy.authorize(nil, request, mode: :enforce_managed)

    assert {:error, :finance_profile_missing} =
             EntitlementPolicy.authorize(nil, request, mode: :enforce_all)

    assert :ok =
             EntitlementPolicy.authorize(nil, request,
               mode: :enforce_all,
               actor_role: :admin
             )
  end
end
