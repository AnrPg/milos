defmodule Palee.Finance.Ports.FinanceStore do
  @callback create_package(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_package(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback retire_package(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_packages() :: [map()]
  @callback get_package(Ecto.UUID.t()) :: map() | nil
  @callback upsert_membership(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_member_profile(Ecto.UUID.t()) :: map() | nil
  @callback search_member_summaries(map()) :: %{optional(Ecto.UUID.t()) => map()}
  @callback assign_package(Ecto.UUID.t(), Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback record_payment(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_receipt(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback receive_payment(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_manual_credit(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply_credit_to_payment(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback reverse_payment(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback reverse_credit_ledger_entry(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback get_invoice(Ecto.UUID.t()) :: {:ok, struct()} | {:error, :not_found}
  @callback member_shop_terms(Ecto.UUID.t()) ::
              %{membership_id: Ecto.UUID.t(), member_discount_percent: integer() | nil} | nil
  @callback update_invoice_params(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback mark_overdue_invoices() :: :ok | {:error, term()}
  @callback list_finance_cleanup_records(map()) :: [map()]
  @callback soft_delete_finance_record(String.t(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback create_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback generate_renewal_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback issue_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback void_invoice(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply_credit_to_invoice(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback get_entitlement(Ecto.UUID.t()) :: map() | nil
  @callback get_effective_entitlement(Ecto.UUID.t()) :: map() | nil
  @callback package_coverage(Ecto.UUID.t(), [map()]) :: [boolean()]
  @callback reserve_entitlement(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback finalize_entitlement(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback release_entitlement(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback grant_allowance(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback revoke_allowance_grant(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback release_stale_entitlement_reservations(DateTime.t()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback transition_entitlement_source(
              Ecto.UUID.t(),
              String.t(),
              Ecto.UUID.t(),
              atom(),
              :finalize | :release,
              map()
            ) :: {:ok, map()} | {:error, term()}
  @callback list_expiring_memberships(non_neg_integer()) :: [map()]
  @callback operational_queues(map()) :: map()
  @callback financial_summary(map()) :: map()
  @callback package_location_scopes() :: %{optional(String.t()) => :all | [String.t()]}
  @callback create_promotion_campaign(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback list_promotion_campaigns() :: [map()]
  @callback create_promotion_code(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_promotion_codes(Ecto.UUID.t() | nil) :: [map()]
  @doc "Active campaigns flagged `params.member_visible`, with their active codes (two reads)."
  @callback list_member_visible_promotions() :: {campaigns :: [map()], codes :: [map()]}
  @callback redeem_promotion(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_referral_program(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_referral_program(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_referral_programs() :: [map()]
  @callback get_active_referral_program() :: map() | nil
  @callback get_referral_program(Ecto.UUID.t()) :: map() | nil
  @doc "ADR-156: a qualified invite opens a pending referral under its own programme."
  @callback open_attributed_referral(map()) :: {:ok, map()} | {:error, term()}
  @callback count_referral_events_since(Ecto.UUID.t(), DateTime.t()) :: non_neg_integer()
  @callback referral_outcomes([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => map()}
  @callback cancel_subscription(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, term()}
  @callback extend_current_subscription(Ecto.UUID.t(), pos_integer()) ::
              {:ok, map()} | {:error, term()}
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
  @callback subscriptions_needing_expiry_notice(:expiry_reminder | :grace_notice, integer()) ::
              [map()]
  @callback mark_subscription_notice_sent(Ecto.UUID.t(), :expiry_reminder | :grace_notice) :: :ok
  @doc "ADR-220: the member's (or staff's) renewal choice for one subscription."
  @callback set_subscription_auto_renew(Ecto.UUID.t(), String.t(), boolean(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @doc "ADR-220: the last day a member leaving today would keep, or nil without a membership."
  @callback membership_leave_preview(Ecto.UUID.t()) :: Date.t() | nil
  @doc "ADR-220: the member leaves the box (`by` member) or staff mark them as left."
  @callback leave_membership(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback undo_leave_membership(Ecto.UUID.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @doc "Refreshes every snapshot; returns the memberships that lost access."
  @callback refresh_entitlement_snapshots() :: [map()]
  @callback total_outstanding_balance_cents() :: non_neg_integer()
  @callback count_pending_referral_approvals() :: non_neg_integer()

  @callback create_freeze(binary(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback cancel_freeze(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_freezes(binary()) :: [map()]
  @callback booking_terms(binary(), Date.t()) :: map()
  @callback allowance_terms(binary(), atom(), Date.t()) :: map() | nil
  # ADR-098 payment models
  @callback list_beneficiaries(binary()) :: [map()]
  @callback add_beneficiary(binary(), binary(), binary(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback remove_beneficiary(binary(), binary()) :: {:ok, map()} | {:error, term()}
  @callback list_corporate_clients() :: [map()]
  @callback get_corporate_client(binary()) :: map() | nil
  @callback find_corporate_client(map()) :: map() | nil
  @callback create_corporate_client(map()) :: {:ok, map()} | {:error, term()}
  @callback update_corporate_client(binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback enroll_corporate_seat(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback end_corporate_seat(binary(), binary()) :: {:ok, map()} | {:error, term()}
  @callback list_corporate_seats(binary()) :: [map()]
  @callback end_email_domain_seats([binary()], String.t() | nil) ::
              {:ok, [map()]} | {:error, term()}
  @callback generate_corporate_invoice(binary(), Date.t()) :: {:ok, map()} | {:error, term()}
  @callback list_corporate_invoices(binary()) :: [map()]
  @callback set_corporate_invoice_status(binary(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_corporate_invoice(String.t()) :: map() | nil
  @callback record_corporate_payment(String.t(), String.t() | nil, map()) ::
              {:ok, map()} | {:error, term()}
  @callback reverse_corporate_payment(String.t(), String.t(), String.t() | nil, map()) ::
              {:ok, map()} | {:error, term()}
  @callback issue_due_corporate_invoices(Date.t()) :: [map()]
  @callback mark_overdue_corporate_invoices(Date.t()) :: non_neg_integer()
  @callback corporate_invoices_needing_reminder(Date.t(), pos_integer()) :: [map()]
  @callback mark_corporate_invoice_reminded(String.t(), Date.t()) ::
              {:ok, map()} | {:error, term()}
  @callback subscriptions_due_for_expiry_reminder(Date.t()) :: [map()]
end
