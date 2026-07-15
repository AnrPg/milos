defmodule MilosTraining.Finance.Domain.ReferralPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.ReferralPolicy

  test "rejects self-referrals and mismatched membership ownership" do
    assert {:error, :self_referral_not_allowed} =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "same",
               referred_user_id: "same",
               membership_user_id: "same"
             })

    assert {:error, :referral_membership_required} =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "a",
               referred_user_id: "b",
               membership_user_id: nil
             })

    assert {:error, :referral_membership_user_mismatch} =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "a",
               referred_user_id: "b",
               membership_user_id: "c"
             })
  end

  test "requires member or athlete participants" do
    assert {:error, :referral_referrer_role_ineligible} =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "a",
               referred_user_id: "b",
               membership_user_id: "b",
               referrer_role: "admin",
               referred_role: "member"
             })

    assert {:error, :referral_referred_role_ineligible} =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "a",
               referred_user_id: "b",
               membership_user_id: "b",
               referrer_role: "member",
               referred_role: "admin"
             })

    assert :ok =
             ReferralPolicy.validate_event(%{
               referrer_user_id: "a",
               referred_user_id: "b",
               membership_user_id: "b",
               referrer_role: "athlete",
               referred_role: "member"
             })
  end

  test "requires approved event and one reward per event" do
    assert {:error, :referral_event_not_approved} =
             ReferralPolicy.validate_reward_creation("pending", false)

    assert {:error, :referral_reward_already_exists} =
             ReferralPolicy.validate_reward_creation("approved", true)

    assert :ok = ReferralPolicy.validate_reward_creation("approved", false)
  end
end
