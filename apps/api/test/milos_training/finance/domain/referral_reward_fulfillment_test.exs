defmodule MilosTraining.Finance.Domain.ReferralRewardFulfillmentTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.ReferralRewardFulfillment

  test "credit rewards require a positive grant amount" do
    assert {:ok, {:credit_grant, 1500}} =
             ReferralRewardFulfillment.plan(%{reward_type: "credit", reward_value: 1500})

    assert {:error, :invalid_credit_amount} =
             ReferralRewardFulfillment.plan(%{reward_type: "credit", reward_value: 0})
  end

  test "free periods and manual rewards are lifecycle-only fulfillment" do
    for reward_type <- ["free_period", "manual"] do
      assert {:ok, :lifecycle_only} =
               ReferralRewardFulfillment.plan(%{reward_type: reward_type, reward_value: 0})
    end
  end

  test "a discount waits for the next renewal and never passes the whole amount" do
    assert {:ok, :renewal_discount} =
             ReferralRewardFulfillment.plan(%{reward_type: "discount", reward_value: 10})

    rewards = [%{reward_value: 10}, %{reward_value: 15}]
    assert ReferralRewardFulfillment.renewal_discount_cents(rewards, 6_000) == 1_500
    assert ReferralRewardFulfillment.renewal_discount_cents([], 6_000) == 0

    assert ReferralRewardFulfillment.renewal_discount_cents(
             [%{reward_value: 80}, %{reward_value: 50}],
             6_000
           ) ==
             6_000
  end
end
