defmodule MilosTraining.Finance.Domain.ReferralRewardFulfillment do
  alias MilosTraining.Finance.Domain.CreditLedger

  def plan(%{reward_type: "credit"} = reward) do
    with {:ok, amount_cents} <- CreditLedger.referral_reward_grant_amount(reward) do
      {:ok, {:credit_grant, amount_cents}}
    end
  end

  def plan(%{reward_type: reward_type})
      when reward_type in ["discount", "free_period", "manual"] do
    {:ok, :lifecycle_only}
  end

  def plan(_reward), do: {:error, :invalid_referral_reward_type}
end
