defmodule MilosTraining.Finance do
  alias MilosTraining.Finance.FinanceStore

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: FinanceStore.with_tenant_context(context, fun)

  defp scoped(context, fun) when is_function(fun, 0),
    do: with_tenant_context(context, fun)

  alias MilosTraining.Finance.Commands.{
    ApplyCreditToPayment,
    AssignPackage,
    ApplyCreditToInvoice,
    CreateInvoice,
    CreateReceipt,
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
    RetirePackage,
    RevokeAllowanceGrant,
    SoftDeleteFinanceRecord,
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
    ListFinanceCleanupRecords,
    SearchMemberSummaries
  }

  defdelegate create_package(params), to: CreatePackage, as: :call
  def create_package(context, params), do: scoped(context, fn -> create_package(params) end)
  defdelegate update_package(id, params), to: UpdatePackage, as: :call

  def update_package(context, id, params),
    do: scoped(context, fn -> update_package(id, params) end)

  defdelegate retire_package(id, replacement_package_by_role), to: RetirePackage, as: :call

  def retire_package(context, id, replacement_package_by_role),
    do: scoped(context, fn -> retire_package(id, replacement_package_by_role) end)

  defdelegate list_packages(), to: ListPackages, as: :call
  def list_packages(context), do: scoped(context, fn -> list_packages() end)
  defdelegate get_package(id), to: GetPackage, as: :call
  def get_package(context, id), do: scoped(context, fn -> get_package(id) end)
  defdelegate upsert_membership(user_id, params), to: UpsertMembership, as: :call

  def upsert_membership(context, user_id, params),
    do: scoped(context, fn -> upsert_membership(user_id, params) end)

  defdelegate get_member_profile(user_id), to: GetMemberProfile, as: :call

  def get_member_profile(context, user_id),
    do: scoped(context, fn -> get_member_profile(user_id) end)

  defdelegate search_member_summaries(params), to: SearchMemberSummaries, as: :call

  def search_member_summaries(context, params),
    do: scoped(context, fn -> search_member_summaries(params) end)

  defdelegate assign_package(membership_id, package_id, params), to: AssignPackage, as: :call

  def assign_package(context, membership_id, package_id, params),
    do: scoped(context, fn -> assign_package(membership_id, package_id, params) end)

  defdelegate record_payment(membership_id, params), to: RecordPayment, as: :call

  def record_payment(context, membership_id, params),
    do: scoped(context, fn -> record_payment(membership_id, params) end)

  defdelegate create_receipt(membership_id, params), to: CreateReceipt, as: :call

  def create_receipt(context, membership_id, params),
    do: scoped(context, fn -> create_receipt(membership_id, params) end)

  defdelegate create_manual_credit(membership_id, params), to: CreateManualCredit, as: :call

  def create_manual_credit(context, membership_id, params),
    do: scoped(context, fn -> create_manual_credit(membership_id, params) end)

  defdelegate apply_credit_to_payment(membership_id, payment_id, params),
    to: ApplyCreditToPayment,
    as: :call

  def apply_credit_to_payment(context, membership_id, payment_id, params),
    do: scoped(context, fn -> apply_credit_to_payment(membership_id, payment_id, params) end)

  defdelegate reverse_payment(membership_id, payment_id, params),
    to: ReversePayment,
    as: :call

  def reverse_payment(context, membership_id, payment_id, params),
    do: scoped(context, fn -> reverse_payment(membership_id, payment_id, params) end)

  defdelegate reverse_credit_ledger_entry(membership_id, entry_id, params),
    to: ReverseCreditLedgerEntry,
    as: :call

  def reverse_credit_ledger_entry(context, membership_id, entry_id, params),
    do: scoped(context, fn -> reverse_credit_ledger_entry(membership_id, entry_id, params) end)

  defdelegate get_invoice(invoice_id), to: FinanceStore, as: :get_invoice
  def get_invoice(context, invoice_id), do: scoped(context, fn -> get_invoice(invoice_id) end)

  defdelegate update_invoice_params(invoice_id, params),
    to: FinanceStore,
    as: :update_invoice_params

  def update_invoice_params(context, invoice_id, params),
    do: scoped(context, fn -> update_invoice_params(invoice_id, params) end)

  defdelegate update_invoice(invoice_id, params), to: FinanceStore, as: :update_invoice

  def update_invoice(context, invoice_id, params),
    do: scoped(context, fn -> update_invoice(invoice_id, params) end)

  defdelegate mark_overdue_invoices(), to: FinanceStore, as: :mark_overdue_invoices
  def mark_overdue_invoices(context), do: scoped(context, fn -> mark_overdue_invoices() end)
  defdelegate list_finance_cleanup_records(params), to: ListFinanceCleanupRecords, as: :call

  def list_finance_cleanup_records(context, params),
    do: scoped(context, fn -> list_finance_cleanup_records(params) end)

  defdelegate soft_delete_finance_record(record_type, record_id, admin_id, params),
    to: SoftDeleteFinanceRecord,
    as: :call

  def soft_delete_finance_record(context, record_type, record_id, admin_id, params),
    do:
      scoped(context, fn ->
        soft_delete_finance_record(record_type, record_id, admin_id, params)
      end)

  defdelegate create_invoice(membership_id, params), to: CreateInvoice, as: :call

  def create_invoice(context, membership_id, params),
    do: scoped(context, fn -> create_invoice(membership_id, params) end)

  defdelegate generate_renewal_invoice(membership_id, params),
    to: GenerateRenewalInvoice,
    as: :call

  def generate_renewal_invoice(context, membership_id, params),
    do: scoped(context, fn -> generate_renewal_invoice(membership_id, params) end)

  defdelegate issue_invoice(invoice_id, params \\ %{}), to: IssueInvoice, as: :call

  def issue_invoice(context, invoice_id, params),
    do: scoped(context, fn -> issue_invoice(invoice_id, params) end)

  defdelegate void_invoice(invoice_id, params \\ %{}), to: VoidInvoice, as: :call

  def void_invoice(context, invoice_id, params),
    do: scoped(context, fn -> void_invoice(invoice_id, params) end)

  defdelegate apply_credit_to_invoice(membership_id, invoice_id, params),
    to: ApplyCreditToInvoice,
    as: :call

  def apply_credit_to_invoice(context, membership_id, invoice_id, params),
    do: scoped(context, fn -> apply_credit_to_invoice(membership_id, invoice_id, params) end)

  defdelegate get_entitlement(user_id), to: GetEntitlement, as: :call
  def get_entitlement(context, user_id), do: scoped(context, fn -> get_entitlement(user_id) end)
  defdelegate get_effective_entitlement(user_id), to: GetEffectiveEntitlement, as: :call

  def get_effective_entitlement(context, user_id),
    do: scoped(context, fn -> get_effective_entitlement(user_id) end)

  defdelegate reserve_entitlement(user_id, request), to: ReserveEntitlement, as: :call

  def reserve_entitlement(context, user_id, request),
    do: scoped(context, fn -> reserve_entitlement(user_id, request) end)

  defdelegate finalize_entitlement(reservation_id, params), to: FinalizeEntitlement, as: :call

  def finalize_entitlement(context, reservation_id, params),
    do: scoped(context, fn -> finalize_entitlement(reservation_id, params) end)

  defdelegate release_entitlement(reservation_id, params), to: ReleaseEntitlement, as: :call

  def release_entitlement(context, reservation_id, params),
    do: scoped(context, fn -> release_entitlement(reservation_id, params) end)

  defdelegate grant_allowance(user_id, admin_id, params), to: GrantAllowance, as: :call

  def grant_allowance(context, user_id, admin_id, params),
    do: scoped(context, fn -> grant_allowance(user_id, admin_id, params) end)

  defdelegate revoke_allowance_grant(user_id, admin_id, grant_id, params),
    to: RevokeAllowanceGrant,
    as: :call

  def revoke_allowance_grant(context, user_id, admin_id, grant_id, params),
    do: scoped(context, fn -> revoke_allowance_grant(user_id, admin_id, grant_id, params) end)

  defdelegate release_stale_entitlement_reservations(cutoff),
    to: ReleaseStaleEntitlementReservations,
    as: :call

  def release_stale_entitlement_reservations(context, cutoff),
    do: scoped(context, fn -> release_stale_entitlement_reservations(cutoff) end)

  defdelegate finalize_entitlement_source(user_id, source_context, source_id, allowance, params),
    to: FinalizeEntitlementSource,
    as: :call

  def finalize_entitlement_source(context, user_id, source_context, source_id, allowance, params),
    do:
      scoped(context, fn ->
        finalize_entitlement_source(user_id, source_context, source_id, allowance, params)
      end)

  defdelegate release_entitlement_source(user_id, source_context, source_id, allowance, params),
    to: ReleaseEntitlementSource,
    as: :call

  def release_entitlement_source(context, user_id, source_context, source_id, allowance, params),
    do:
      scoped(context, fn ->
        release_entitlement_source(user_id, source_context, source_id, allowance, params)
      end)

  defdelegate list_expiring_memberships(days), to: ListExpiringMemberships, as: :call

  def list_expiring_memberships(context, days),
    do: scoped(context, fn -> list_expiring_memberships(days) end)

  defdelegate operational_queues(params \\ %{}), to: OperationalQueues, as: :call

  def operational_queues(context, params),
    do: scoped(context, fn -> operational_queues(params) end)

  def financial_summary(params \\ %{}), do: FinancialSummary.call(params)
  def financial_summary(context, params), do: scoped(context, fn -> financial_summary(params) end)
  defdelegate create_promotion_campaign(params), to: CreatePromotionCampaign, as: :call

  def create_promotion_campaign(context, params),
    do: scoped(context, fn -> create_promotion_campaign(params) end)

  defdelegate list_promotion_campaigns(), to: ListPromotionCampaigns, as: :call

  def list_promotion_campaigns(context),
    do: scoped(context, fn -> list_promotion_campaigns() end)

  defdelegate create_promotion_code(campaign_id, params), to: CreatePromotionCode, as: :call

  def create_promotion_code(context, campaign_id, params),
    do: scoped(context, fn -> create_promotion_code(campaign_id, params) end)

  defdelegate list_promotion_codes(campaign_id \\ nil), to: ListPromotionCodes, as: :call

  def list_promotion_codes(context, campaign_id),
    do: scoped(context, fn -> list_promotion_codes(campaign_id) end)

  defdelegate redeem_promotion(membership_id, params), to: RedeemPromotion, as: :call

  def redeem_promotion(context, membership_id, params),
    do: scoped(context, fn -> redeem_promotion(membership_id, params) end)

  defdelegate create_referral_program(params), to: CreateReferralProgram, as: :call

  def create_referral_program(context, params),
    do: scoped(context, fn -> create_referral_program(params) end)

  defdelegate update_referral_program(id, params), to: UpdateReferralProgram, as: :call

  def update_referral_program(context, id, params),
    do: scoped(context, fn -> update_referral_program(id, params) end)

  defdelegate list_referral_programs(), to: ListReferralPrograms, as: :call
  def list_referral_programs(context), do: scoped(context, fn -> list_referral_programs() end)
  defdelegate create_referral_event(params), to: CreateReferralEvent, as: :call

  def create_referral_event(context, params),
    do: scoped(context, fn -> create_referral_event(params) end)

  defdelegate update_referral_status(id, status), to: UpdateReferralStatus, as: :call

  def update_referral_status(context, id, status),
    do: scoped(context, fn -> update_referral_status(id, status) end)

  defdelegate list_referral_events(), to: ListReferralEvents, as: :call
  def list_referral_events(context), do: scoped(context, fn -> list_referral_events() end)

  defdelegate create_referral_reward(referral_event_id, params),
    to: CreateReferralReward,
    as: :call

  def create_referral_reward(context, referral_event_id, params),
    do: scoped(context, fn -> create_referral_reward(referral_event_id, params) end)

  defdelegate list_referral_rewards(), to: ListReferralRewards, as: :call
  def list_referral_rewards(context), do: scoped(context, fn -> list_referral_rewards() end)
  defdelegate update_referral_reward_status(id, status), to: UpdateReferralRewardStatus, as: :call

  def update_referral_reward_status(context, id, status),
    do: scoped(context, fn -> update_referral_reward_status(id, status) end)

  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call
  def refresh_aggregates(context), do: scoped(context, fn -> refresh_aggregates() end)

  defdelegate get_finance_settings(), to: FinanceStore, as: :get_finance_settings
  def get_finance_settings(context), do: scoped(context, fn -> get_finance_settings() end)
  defdelegate update_finance_settings(params), to: FinanceStore, as: :update_finance_settings

  def update_finance_settings(context, params),
    do: scoped(context, fn -> update_finance_settings(params) end)

  defdelegate membership_outstanding_balance_cents(membership_id),
    to: FinanceStore,
    as: :membership_outstanding_balance_cents

  def membership_outstanding_balance_cents(context, membership_id),
    do: scoped(context, fn -> membership_outstanding_balance_cents(membership_id) end)

  defdelegate invoice_balance_due_map(invoice_ids),
    to: FinanceStore,
    as: :invoice_balance_due_map

  def invoice_balance_due_map(context, invoice_ids),
    do: scoped(context, fn -> invoice_balance_due_map(invoice_ids) end)

  defdelegate memberships_needing_payment_reminder(interval_days),
    to: FinanceStore,
    as: :memberships_needing_payment_reminder

  def memberships_needing_payment_reminder(context, interval_days),
    do: scoped(context, fn -> memberships_needing_payment_reminder(interval_days) end)

  defdelegate update_membership_reminder_timestamp(membership_id),
    to: FinanceStore,
    as: :update_membership_reminder_timestamp

  def update_membership_reminder_timestamp(context, membership_id),
    do: scoped(context, fn -> update_membership_reminder_timestamp(membership_id) end)

  defdelegate total_outstanding_balance_cents(),
    to: FinanceStore,
    as: :total_outstanding_balance_cents

  def total_outstanding_balance_cents(context),
    do: scoped(context, fn -> total_outstanding_balance_cents() end)

  defdelegate count_pending_referral_approvals(),
    to: FinanceStore,
    as: :count_pending_referral_approvals

  def count_pending_referral_approvals(context),
    do: scoped(context, fn -> count_pending_referral_approvals() end)
end
