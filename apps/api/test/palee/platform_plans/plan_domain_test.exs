defmodule Palee.PlatformPlans.PlanDomainTest do
  use ExUnit.Case, async: true

  alias Palee.PlatformPlans.Domain.{PlanLimits, SubscriptionPolicy}

  @now ~U[2026-11-17 10:00:00.000000Z]

  describe "PlanLimits" do
    test "parses known positive limits; nil means unlimited; unknown keys are refused" do
      assert {:ok, %{"staff_seats" => 2}} =
               PlanLimits.parse(%{staff_seats: 2, active_clients: nil})

      assert {:error, :invalid_plan_limits} = PlanLimits.parse(%{"staf_seats" => 2})
      assert {:error, :invalid_plan_limits} = PlanLimits.parse(%{"staff_seats" => 0})
      assert {:error, :invalid_plan_limits} = PlanLimits.parse(%{"staff_seats" => "3"})
    end

    test "only the hard staff-seat limit refuses" do
      limits = %{"staff_seats" => 2, "active_clients" => 3}

      assert :ok = PlanLimits.check(limits, "staff_seats", 1)
      assert {:error, :plan_limit_reached} = PlanLimits.check(limits, "staff_seats", 2)
      # Clients are never turned away for the coach's plan.
      assert :ok = PlanLimits.check(limits, "active_clients", 30)
      assert :ok = PlanLimits.check(%{}, "staff_seats", 500)
    end

    test "usage rows carry a state per limit" do
      rows =
        PlanLimits.usage(%{"staff_seats" => 2, "active_clients" => 10}, %{
          "staff_seats" => 2,
          "active_clients" => 9
        })

      assert [
               %{key: "staff_seats", used: 2, limit: 2, hard: true, state: :reached},
               %{key: "active_clients", used: 9, limit: 10, hard: false, state: :near}
             ] = rows

      assert [%{limit: :unlimited, state: :ok}, %{state: :ok}] = PlanLimits.usage(%{}, %{})
    end
  end

  describe "SubscriptionPolicy" do
    test "a trial past its end reads trial_expired and warns in its last week" do
      running = %{status: "trialing", trial_ends_at: DateTime.add(@now, 20 * 86_400)}
      ending = %{status: "trialing", trial_ends_at: DateTime.add(@now, 3 * 86_400 - 60)}
      ended = %{status: "trialing", trial_ends_at: DateTime.add(@now, -1)}

      assert "trialing" == SubscriptionPolicy.effective_status(running, @now)
      assert nil == SubscriptionPolicy.notice(running, @now)
      assert 20 == SubscriptionPolicy.trial_days_left(running, @now)
      assert "trial_ending" == SubscriptionPolicy.notice(ending, @now)
      assert 3 == SubscriptionPolicy.trial_days_left(ending, @now)
      assert "trial_expired" == SubscriptionPolicy.effective_status(ended, @now)
      assert "trial_expired" == SubscriptionPolicy.notice(ended, @now)
      assert nil == SubscriptionPolicy.notice(%{status: "comped", trial_ends_at: nil}, @now)

      assert "past_due" ==
               SubscriptionPolicy.notice(%{status: "past_due", trial_ends_at: nil}, @now)
    end

    test "a vendor's assignment needs a future trial end only for a trial" do
      future = DateTime.add(@now, 86_400)

      assert {:ok, %{status: "active", trial_ends_at: nil}} =
               SubscriptionPolicy.validate_assignment(
                 %{"status" => "active", "trial_ends_at" => future},
                 @now
               )

      assert {:ok, %{status: "trialing", trial_ends_at: ^future}} =
               SubscriptionPolicy.validate_assignment(
                 %{status: "trialing", trial_ends_at: future},
                 @now
               )

      assert {:error, :trial_end_required} =
               SubscriptionPolicy.validate_assignment(%{status: "trialing"}, @now)

      assert {:error, :invalid_subscription_status} =
               SubscriptionPolicy.validate_assignment(%{status: "free"}, @now)

      assert {:error, :invalid_price} =
               SubscriptionPolicy.validate_assignment(
                 %{status: "active", price_override_cents: -1},
                 @now
               )
    end
  end
end
