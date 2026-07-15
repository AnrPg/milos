defmodule MilosTraining.Finance do
  alias MilosTraining.Finance.FinanceStore

  alias MilosTraining.Finance.Commands.{
    ApplyCreditToPayment,
    AssignPackage,
    ApplyCreditToInvoice,
    CreateInvoice,
    CreateManualCredit,
    CreatePackage,
    CreatePromotionCampaign,
    CreatePromotionCode,
    CreateReferralEvent,
    CreateReferralProgram,
    CreateReferralReward,
    GenerateRenewalInvoice,
    FinalizeEntitlementSource,
    GrantAllowance,
    IssueInvoice,
    RecordPayment,
    ReleaseEntitlement,
    ReleaseEntitlementSource,
    ReleaseStaleEntitlementReservations,
    ReserveEntitlement,
    FinalizeEntitlement,
    RedeemPromotion,
    RefreshAggregates,
    ReverseCreditLedgerEntry,
    ReversePayment,
    RevokeAllowanceGrant,
    UpdatePackage,
    UpdateReferralRewardStatus,
    UpdateReferralProgram,
    UpdateReferralStatus,
    VoidInvoice,
    UpsertMembership
  }

  alias MilosTraining.Finance.Queries.{
    FinancialSummary,
    GetEntitlement,
    GetEffectiveEntitlement,
    GetMemberProfile,
    GetPackage,
    ListExpiringMemberships,
    ListPackages,
    ListPromotionCampaigns,
    ListPromotionCodes,
    ListReferralPrograms,
    ListReferralEvents,
    ListReferralRewards,
    OperationalQueues,
    SearchMemberSummaries
  }

  defdelegate create_package(params), to: CreatePackage, as: :call
  defdelegate update_package(id, params), to: UpdatePackage, as: :call
  defdelegate list_packages(), to: ListPackages, as: :call
  defdelegate get_package(id), to: GetPackage, as: :call
  defdelegate upsert_membership(user_id, params), to: UpsertMembership, as: :call
  defdelegate get_member_profile(user_id), to: GetMemberProfile, as: :call
  defdelegate search_member_summaries(params), to: SearchMemberSummaries, as: :call
  defdelegate assign_package(membership_id, package_id, params), to: AssignPackage, as: :call
  defdelegate record_payment(membership_id, params), to: RecordPayment, as: :call
  defdelegate create_manual_credit(membership_id, params), to: CreateManualCredit, as: :call

  defdelegate apply_credit_to_payment(membership_id, payment_id, params),
    to: ApplyCreditToPayment,
    as: :call

  defdelegate reverse_payment(membership_id, payment_id, params),
    to: ReversePayment,
    as: :call

  defdelegate reverse_credit_ledger_entry(membership_id, entry_id, params),
    to: ReverseCreditLedgerEntry,
    as: :call

  defdelegate get_invoice(invoice_id), to: FinanceStore, as: :get_invoice

  defdelegate update_invoice_params(invoice_id, params),
    to: FinanceStore,
    as: :update_invoice_params

  defdelegate update_invoice(invoice_id, params), to: FinanceStore, as: :update_invoice
  defdelegate mark_overdue_invoices(), to: FinanceStore, as: :mark_overdue_invoices
  defdelegate create_invoice(membership_id, params), to: CreateInvoice, as: :call

  defdelegate generate_renewal_invoice(membership_id, params),
    to: GenerateRenewalInvoice,
    as: :call

  defdelegate issue_invoice(invoice_id, params \\ %{}), to: IssueInvoice, as: :call
  defdelegate void_invoice(invoice_id, params \\ %{}), to: VoidInvoice, as: :call

  defdelegate apply_credit_to_invoice(membership_id, invoice_id, params),
    to: ApplyCreditToInvoice,
    as: :call

  defdelegate get_entitlement(user_id), to: GetEntitlement, as: :call
  defdelegate get_effective_entitlement(user_id), to: GetEffectiveEntitlement, as: :call
  defdelegate reserve_entitlement(user_id, request), to: ReserveEntitlement, as: :call
  defdelegate finalize_entitlement(reservation_id, params), to: FinalizeEntitlement, as: :call
  defdelegate release_entitlement(reservation_id, params), to: ReleaseEntitlement, as: :call
  defdelegate grant_allowance(user_id, admin_id, params), to: GrantAllowance, as: :call

  defdelegate revoke_allowance_grant(user_id, admin_id, grant_id, params),
    to: RevokeAllowanceGrant,
    as: :call

  defdelegate release_stale_entitlement_reservations(cutoff),
    to: ReleaseStaleEntitlementReservations,
    as: :call

  defdelegate finalize_entitlement_source(user_id, source_context, source_id, allowance, params),
    to: FinalizeEntitlementSource,
    as: :call

  defdelegate release_entitlement_source(user_id, source_context, source_id, allowance, params),
    to: ReleaseEntitlementSource,
    as: :call

  defdelegate list_expiring_memberships(days), to: ListExpiringMemberships, as: :call
  defdelegate operational_queues(params \\ %{}), to: OperationalQueues, as: :call
  def financial_summary(params \\ %{}), do: FinancialSummary.call(params)
  defdelegate create_promotion_campaign(params), to: CreatePromotionCampaign, as: :call
  defdelegate list_promotion_campaigns(), to: ListPromotionCampaigns, as: :call
  defdelegate create_promotion_code(campaign_id, params), to: CreatePromotionCode, as: :call
  defdelegate list_promotion_codes(campaign_id \\ nil), to: ListPromotionCodes, as: :call
  defdelegate redeem_promotion(membership_id, params), to: RedeemPromotion, as: :call
  defdelegate create_referral_program(params), to: CreateReferralProgram, as: :call
  defdelegate update_referral_program(id, params), to: UpdateReferralProgram, as: :call
  defdelegate list_referral_programs(), to: ListReferralPrograms, as: :call
  defdelegate create_referral_event(params), to: CreateReferralEvent, as: :call
  defdelegate update_referral_status(id, status), to: UpdateReferralStatus, as: :call
  defdelegate list_referral_events(), to: ListReferralEvents, as: :call

  defdelegate create_referral_reward(referral_event_id, params),
    to: CreateReferralReward,
    as: :call

  defdelegate list_referral_rewards(), to: ListReferralRewards, as: :call
  defdelegate update_referral_reward_status(id, status), to: UpdateReferralRewardStatus, as: :call
  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call

  defdelegate get_finance_settings(), to: FinanceStore, as: :get_finance_settings
  defdelegate update_finance_settings(params), to: FinanceStore, as: :update_finance_settings

  defdelegate membership_outstanding_balance_cents(membership_id),
    to: FinanceStore,
    as: :membership_outstanding_balance_cents

  defdelegate invoice_balance_due_map(invoice_ids),
    to: FinanceStore,
    as: :invoice_balance_due_map

  defdelegate memberships_needing_payment_reminder(interval_days),
    to: FinanceStore,
    as: :memberships_needing_payment_reminder

  defdelegate update_membership_reminder_timestamp(membership_id),
    to: FinanceStore,
    as: :update_membership_reminder_timestamp

  defdelegate total_outstanding_balance_cents(),
    to: FinanceStore,
    as: :total_outstanding_balance_cents

  defdelegate count_pending_referral_approvals(),
    to: FinanceStore,
    as: :count_pending_referral_approvals
end
