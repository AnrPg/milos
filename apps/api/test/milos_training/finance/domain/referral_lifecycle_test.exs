defmodule MilosTraining.Finance.Domain.ReferralLifecycleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.ReferralLifecycle

  test "allows forward referral transitions" do
    assert :ok = ReferralLifecycle.validate_transition("pending", "approved")
    assert :ok = ReferralLifecycle.validate_transition("pending", "rejected")
    assert :ok = ReferralLifecycle.validate_transition("approved", "applied")
    assert :ok = ReferralLifecycle.validate_transition("approved", "rejected")
  end

  test "allows idempotent transitions" do
    assert :ok = ReferralLifecycle.validate_transition("pending", "pending")
    assert :ok = ReferralLifecycle.validate_transition("applied", "applied")
  end

  test "blocks terminal and skipped transitions" do
    assert {:error, :invalid_referral_status_transition} =
             ReferralLifecycle.validate_transition("pending", "applied")

    assert {:error, :invalid_referral_status_transition} =
             ReferralLifecycle.validate_transition("applied", "approved")

    assert {:error, :invalid_referral_status_transition} =
             ReferralLifecycle.validate_transition("rejected", "approved")
  end

  test "allows rewards to be approved or rejected repeatedly" do
    assert :ok = ReferralLifecycle.validate_reward_transition("pending", "applied")
    assert :ok = ReferralLifecycle.validate_reward_transition("pending", "rejected")
    assert :ok = ReferralLifecycle.validate_reward_transition("rejected", "applied")
    assert :ok = ReferralLifecycle.validate_reward_transition("applied", "rejected")
    assert :ok = ReferralLifecycle.validate_reward_transition("applied", "applied")
  end
end
