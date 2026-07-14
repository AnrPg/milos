defmodule MilosTraining.Finance.Domain.CreditLedger do
  @grant_types ["manual_credit", "promo_credit", "referral_reward"]
  @creditable_payment_statuses ["paid", "pending"]

  def referral_reward_grant_amount(%{reward_value: value}) when is_integer(value) and value > 0 do
    {:ok, value}
  end

  def referral_reward_grant_amount(_reward), do: {:error, :invalid_credit_amount}

  def validate_manual_grant(amount_cents) when is_integer(amount_cents) and amount_cents > 0,
    do: :ok

  def validate_manual_grant(_amount_cents), do: {:error, :invalid_credit_amount}

  def validate_application(available_cents, amount_cents, payment_amount_cents)
      when is_integer(available_cents) and is_integer(amount_cents) and
             is_integer(payment_amount_cents) do
    cond do
      amount_cents <= 0 -> {:error, :invalid_credit_amount}
      amount_cents > available_cents -> {:error, :insufficient_credit_balance}
      amount_cents > payment_amount_cents -> {:error, :credit_exceeds_payment_amount}
      true -> :ok
    end
  end

  def validate_application(_available_cents, _amount_cents, _payment_amount_cents),
    do: {:error, :invalid_credit_amount}

  def validate_payment_status(status) when status in @creditable_payment_statuses, do: :ok
  def validate_payment_status(_status), do: {:error, :payment_not_creditable}

  def validate_reversal(original_entry, already_reversed_cents, amount_cents)
      when is_integer(already_reversed_cents) and is_integer(amount_cents) do
    original_amount =
      Map.get(original_entry, :amount_cents) || Map.get(original_entry, "amount_cents")

    entry_type = Map.get(original_entry, :entry_type) || Map.get(original_entry, "entry_type")
    source_type = Map.get(original_entry, :source_type) || Map.get(original_entry, "source_type")
    reversible_types = ["application", "invoice_offset"]
    reversible_sources = ["payment_application", "invoice_offset"]
    remaining_cents = abs(original_amount || 0) - already_reversed_cents

    cond do
      not is_integer(original_amount) ->
        {:error, :credit_entry_not_reversible}

      original_amount >= 0 ->
        {:error, :credit_entry_not_reversible}

      entry_type not in reversible_types or source_type not in reversible_sources ->
        {:error, :credit_entry_not_reversible}

      amount_cents <= 0 ->
        {:error, :invalid_credit_amount}

      amount_cents > remaining_cents ->
        {:error, :credit_reversal_exceeds_application}

      true ->
        :ok
    end
  end

  def validate_reversal(_original_entry, _already_reversed_cents, _amount_cents),
    do: {:error, :invalid_credit_amount}

  def normalize_grant_amount(source_type, amount_cents)
      when source_type in @grant_types and is_integer(amount_cents) and amount_cents > 0 do
    {:ok, amount_cents}
  end

  def normalize_grant_amount(_source_type, _amount_cents), do: {:error, :invalid_credit_amount}

  def creditable_payment_statuses, do: @creditable_payment_statuses
end
