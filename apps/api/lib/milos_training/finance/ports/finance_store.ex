defmodule MilosTraining.Finance.Ports.FinanceStore do
  @callback create_package(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_package(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_packages() :: [map()]
  @callback get_package(Ecto.UUID.t()) :: map() | nil
  @callback upsert_membership(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_member_profile(Ecto.UUID.t()) :: map() | nil
  @callback search_member_summaries(map()) :: %{optional(Ecto.UUID.t()) => map()}
  @callback assign_package(Ecto.UUID.t(), Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback record_payment(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_manual_credit(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply_credit_to_payment(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback reverse_payment(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback reverse_credit_ledger_entry(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback get_invoice(Ecto.UUID.t()) :: {:ok, struct()} | {:error, :not_found}
  @callback update_invoice_params(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback mark_overdue_invoices() :: :ok | {:error, term()}
  @callback create_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback generate_renewal_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback issue_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback void_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply_credit_to_invoice(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback get_entitlement(Ecto.UUID.t()) :: map() | nil
  @callback list_expiring_memberships(non_neg_integer()) :: [map()]
  @callback operational_queues(map()) :: map()
  @callback financial_summary(map()) :: map()
  @callback create_promotion_campaign(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback list_promotion_campaigns() :: [map()]
  @callback create_promotion_code(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_promotion_codes(Ecto.UUID.t() | nil) :: [map()]
  @callback redeem_promotion(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_referral_program(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_referral_program(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_referral_programs() :: [map()]
  @callback create_referral_event(map()) :: {:ok, map()} | {:error, term()}
  @callback update_referral_status(Ecto.UUID.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_referral_events() :: [map()]
  @callback create_referral_reward(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_referral_rewards() :: [map()]
  @callback update_referral_reward_status(Ecto.UUID.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback refresh_aggregates() :: :ok | {:error, term()}
  @callback get_finance_settings() :: map()
  @callback update_finance_settings(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback membership_outstanding_balance_cents(Ecto.UUID.t()) :: non_neg_integer()
  @callback outstanding_balance_per_membership([Ecto.UUID.t()]) ::
              %{optional(Ecto.UUID.t()) => non_neg_integer()}
  @callback invoice_balance_due_map([Ecto.UUID.t()]) ::
              %{optional(Ecto.UUID.t()) => non_neg_integer()}
  @callback update_membership_reminder_timestamp(Ecto.UUID.t()) :: :ok
  @callback memberships_needing_payment_reminder(non_neg_integer()) :: [map()]
  @callback total_outstanding_balance_cents() :: non_neg_integer()
  @callback count_pending_referral_approvals() :: non_neg_integer()
end
