defmodule MilosTraining.Finance.Domain.EntitlementPolicyExplicitTest do
  @moduledoc "ADR-107: explicit (rollout-independent) entitlement grants."
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.EntitlementPolicy

  @request %{channel: :personal_programming, capability: :execute_assigned_workouts}

  @programming_plan %{
    entitlement_version: 1,
    channels: [:in_person, :personal_programming],
    capabilities: [:book_classes, :execute_assigned_workouts],
    allowances: %{}
  }

  @class_only_plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person"],
    "capabilities" => ["book_classes", "execute_class_workouts"],
    "allowances" => %{}
  }

  test "grants only when the plan explicitly includes the channel and capability" do
    assert :ok =
             EntitlementPolicy.authorize_explicit(
               %{status: "active", plan: @programming_plan},
               @request
             )

    assert :ok =
             EntitlementPolicy.authorize_explicit(
               %{status: "grace", plan: @programming_plan},
               @request
             )
  end

  test "denies a missing channel even though the observe rollout would allow it" do
    entitlement = %{status: "active", plan: @class_only_plan}

    assert {:ok, %{observed?: true}} =
             EntitlementPolicy.authorize(entitlement, @request, mode: :observe)

    assert {:error, :finance_channel_not_included} =
             EntitlementPolicy.authorize_explicit(entitlement, @request)
  end

  test "denies a missing capability" do
    plan = %{@programming_plan | capabilities: [:book_classes]}

    assert {:error, :finance_capability_not_included} =
             EntitlementPolicy.authorize_explicit(%{status: "active", plan: plan}, @request)
  end

  test "denies missing profiles, missing plans, and blocked or inactive memberships" do
    assert {:error, :finance_profile_missing} =
             EntitlementPolicy.authorize_explicit(nil, @request)

    assert {:error, :finance_entitlement_plan_missing} =
             EntitlementPolicy.authorize_explicit(%{status: "active", plan: nil}, @request)

    assert {:error, :finance_entitlement_blocked} =
             EntitlementPolicy.authorize_explicit(
               %{status: "blocked", plan: @programming_plan},
               @request
             )

    assert {:error, :finance_entitlement_inactive} =
             EntitlementPolicy.authorize_explicit(
               %{status: "inactive", plan: @programming_plan},
               @request
             )
  end

  test "has no admin-actor bypass: the subject is the customer, not the caller" do
    assert {:error, :finance_profile_missing} =
             EntitlementPolicy.authorize_explicit(nil, Map.put(@request, :actor_role, :admin))
  end
end
