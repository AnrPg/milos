defmodule MilosTraining.Finance.Domain.ReferralLifecycle do
  @terminal_statuses ["applied", "rejected"]
  @valid_statuses ["pending", "approved", "applied", "rejected"]

  def validate_transition(current_status, next_status)
      when current_status in @valid_statuses and next_status in @valid_statuses do
    cond do
      current_status == next_status ->
        :ok

      current_status in @terminal_statuses ->
        {:error, :invalid_referral_status_transition}

      current_status == "pending" and next_status in ["approved", "rejected"] ->
        :ok

      current_status == "approved" and next_status in ["applied", "rejected"] ->
        :ok

      true ->
        {:error, :invalid_referral_status_transition}
    end
  end

  def validate_transition(_current_status, _next_status),
    do: {:error, :invalid_referral_status_transition}

  def validate_reward_transition(current_status, next_status)
      when current_status in @valid_statuses and next_status in @valid_statuses do
    cond do
      current_status == next_status ->
        :ok

      next_status in ["applied", "rejected"] ->
        :ok

      current_status == "pending" and next_status == "approved" ->
        :ok

      true ->
        {:error, :invalid_referral_status_transition}
    end
  end

  def validate_reward_transition(_current_status, _next_status),
    do: {:error, :invalid_referral_status_transition}
end
