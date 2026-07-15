defmodule MilosTraining.Finance.Domain.ReferralRewardFulfillmentTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.ReferralRewardFulfillment

  test "credit rewards require a positive grant amount" do
    assert {:ok, {:credit_grant, 1500}} =
             ReferralRewardFulfillment.plan(%{reward_type: "credit", reward_value: 1500})

    assert {:error, :invalid_credit_amount} =
             ReferralRewardFulfillment.plan(%{reward_type: "credit", reward_value: 0})
  end

  test "non-credit rewards are lifecycle-only fulfillment" do
    for reward_type <- ["discount", "free_period", "manual"] do
      assert {:ok, :lifecycle_only} =
               ReferralRewardFulfillment.plan(%{reward_type: reward_type, reward_value: 0})
    end
  end
end
