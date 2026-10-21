defmodule Palee.Finance.Domain.ReferralRewardFulfillment do
  @moduledoc """
  What giving a referral reward does: a credit lands in the credit ledger; a
  discount (a percentage) waits for the member's next renewal invoice
  (ADR-156, board 11 Q6); a free period or a manual reward only changes its
  status.
  """

  alias Palee.Finance.Domain.CreditLedger

  def plan(%{reward_type: "credit"} = reward) do
    with {:ok, amount_cents} <- CreditLedger.referral_reward_grant_amount(reward) do
      {:ok, {:credit_grant, amount_cents}}
    end
  end

  def plan(%{reward_type: "discount"}), do: {:ok, :renewal_discount}

  def plan(%{reward_type: reward_type})
      when reward_type in ["free_period", "manual"] do
    {:ok, :lifecycle_only}
  end

  def plan(_reward), do: {:error, :invalid_referral_reward_type}

  @doc """
  The discount given discount rewards take off a renewal of `subtotal_cents`:
  their percentages add up, never past the whole amount.
  """
  def renewal_discount_cents(rewards, subtotal_cents)
      when is_list(rewards) and is_integer(subtotal_cents) do
    percent = rewards |> Enum.map(&max(&1.reward_value || 0, 0)) |> Enum.sum() |> min(100)
    div(max(subtotal_cents, 0) * percent, 100)
  end
end
