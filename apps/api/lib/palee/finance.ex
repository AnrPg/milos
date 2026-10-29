defmodule Palee.Finance do
  alias Palee.Finance.{Commands, FinanceStore, Queries}

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: FinanceStore.with_tenant_context(context, fun)

  defp scoped(context, fun) when is_function(fun, 0),
    do: with_tenant_context(context, fun)

  alias Palee.Finance.Commands.{
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
    ReceivePayment,
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

  alias Palee.Finance.Queries.{
    FinancialSummary,
    GetEntitlement,
    GetEffectiveEntitlement,
    GetMemberProfile,
    GetPackage,
    GetPackageCatalog,
    ListExpiringMemberships,
    ListMemberOffers,
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
  defdelegate get_package_catalog(), to: GetPackageCatalog, as: :call

  # Closed package vocabularies used by interface contracts (ADR-096).
  def package_type_keys, do: Palee.Finance.Domain.PackageType.keys()
  def package_billing_periods, do: Palee.Finance.Domain.PackageType.all_billing_periods()
  def package_catalog_fields, do: Palee.Finance.Domain.PackageCatalog.fields()
  def package_module_keys, do: Palee.Finance.Domain.PackageType.module_keys()
  def package_quota_periods, do: Palee.Finance.Domain.PackageCatalog.quota_periods()
  def get_package_catalog(context), do: scoped(context, fn -> get_package_catalog() end)
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

  defdelegate receive_payment(membership_id, params), to: ReceivePayment, as: :call

  def receive_payment(context, membership_id, params),
    do: scoped(context, fn -> receive_payment(membership_id, params) end)

  @doc "ADR-222: how money can reach the box at the desk."
  defdelegate received_payment_methods(), to: Palee.Finance.Domain.ReceivedPayment, as: :methods

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

  @doc "Per booking request, whether the member's package includes it (scope only)."
  def package_coverage(context, user_id, requests),
    do: scoped(context, fn -> FinanceStore.package_coverage(user_id, requests) end)

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

  @doc "ADR-252: people whose subscription to `package_id` covers `date` (bulk document requests)."
  def package_holder_user_ids(context, package_id, %Date{} = date),
    do: scoped(context, fn -> FinanceStore.package_holder_user_ids(package_id, date) end)

  defdelegate operational_queues(params \\ %{}), to: OperationalQueues, as: :call

  def operational_queues(context, params),
    do: scoped(context, fn -> operational_queues(params) end)

  def financial_summary(params \\ %{}), do: FinancialSummary.call(params)
  def financial_summary(context, params), do: scoped(context, fn -> financial_summary(params) end)

  @doc """
  The branches each person's current packages cover, `%{user_id => :all |
  [location_id]}` (ADR-186 §7: the home-branch attribution reads it).
  """
  def package_location_scopes(context),
    do: scoped(context, fn -> FinanceStore.package_location_scopes() end)

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

  @doc "Codes the box shows its members on `today`, for Εγώ › Πληρωμές › Προσφορές."
  def list_member_offers(context, %Date{} = today \\ Date.utc_today()),
    do: scoped(context, fn -> ListMemberOffers.call(today) end)

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
  # ADR-156: what the Referrals context needs from Finance, each in the box's scope.
  def active_referral_program(context),
    do: scoped(context, fn -> FinanceStore.get_active_referral_program() end)

  def get_referral_program(context, id),
    do: scoped(context, fn -> FinanceStore.get_referral_program(id) end)

  def open_attributed_referral(context, params),
    do: scoped(context, fn -> FinanceStore.open_attributed_referral(params) end)

  def count_referral_events_since(context, referrer_user_id, since),
    do:
      scoped(context, fn ->
        FinanceStore.count_referral_events_since(referrer_user_id, since)
      end)

  def referral_outcomes(context, event_ids),
    do: scoped(context, fn -> FinanceStore.referral_outcomes(event_ids) end)

  def extend_current_subscription(context, membership_id, days),
    do: scoped(context, fn -> FinanceStore.extend_current_subscription(membership_id, days) end)

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

  def subscriptions_needing_expiry_notice(context, kind, days),
    do: scoped(context, fn -> FinanceStore.subscriptions_needing_expiry_notice(kind, days) end)

  # ADR-220: renewal choice and leaving the box.
  def set_subscription_auto_renew(context, user_id, subscription_id, auto_renew, by),
    do:
      scoped(context, fn ->
        FinanceStore.set_subscription_auto_renew(user_id, subscription_id, auto_renew, by)
      end)

  def membership_leave_preview(context, user_id),
    do: scoped(context, fn -> FinanceStore.membership_leave_preview(user_id) end)

  def leave_membership(context, user_id, params),
    do: scoped(context, fn -> FinanceStore.leave_membership(user_id, params) end)

  def undo_leave_membership(context, user_id, by),
    do: scoped(context, fn -> FinanceStore.undo_leave_membership(user_id, by) end)

  def mark_subscription_notice_sent(context, subscription_id, kind),
    do:
      scoped(context, fn -> FinanceStore.mark_subscription_notice_sent(subscription_id, kind) end)

  def refresh_entitlement_snapshots(context),
    do: scoped(context, fn -> FinanceStore.refresh_entitlement_snapshots() end)

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

  # ADR-126 refund receipts, payment-provider reconciliation and accounting
  # exports. All of them attach to the append-only payment/reversal facts.
  defdelegate list_refund_receipts(filters), to: Queries.ListRefundReceipts, as: :call

  def list_refund_receipts(context, filters),
    do: scoped(context, fn -> list_refund_receipts(filters) end)

  defdelegate get_refund_receipt(id), to: Queries.GetRefundReceipt, as: :call
  def get_refund_receipt(context, id), do: scoped(context, fn -> get_refund_receipt(id) end)

  defdelegate get_refund_receipt_for_reversal(reversal_id),
    to: Queries.GetRefundReceipt,
    as: :for_reversal

  def get_refund_receipt_for_reversal(context, reversal_id),
    do: scoped(context, fn -> get_refund_receipt_for_reversal(reversal_id) end)

  defdelegate record_reconciliation_line(params, actor_id),
    to: Commands.RecordReconciliationLine,
    as: :call

  def record_reconciliation_line(context, params, actor_id),
    do: scoped(context, fn -> record_reconciliation_line(params, actor_id) end)

  defdelegate list_reconciliation_records(filters),
    to: Queries.ListReconciliationRecords,
    as: :call

  def list_reconciliation_records(context, filters),
    do: scoped(context, fn -> list_reconciliation_records(filters) end)

  defdelegate get_reconciliation_record(id), to: Queries.GetReconciliationRecord, as: :call

  def get_reconciliation_record(context, id),
    do: scoped(context, fn -> get_reconciliation_record(id) end)

  defdelegate reconciliation_candidates(id), to: Queries.ReconciliationCandidates, as: :call

  def reconciliation_candidates(context, id),
    do: scoped(context, fn -> reconciliation_candidates(id) end)

  defdelegate match_reconciliation_record(id, target_type, target_id, attrs),
    to: Commands.MatchReconciliationRecord,
    as: :call

  def match_reconciliation_record(context, id, target_type, target_id, attrs),
    do: scoped(context, fn -> match_reconciliation_record(id, target_type, target_id, attrs) end)

  defdelegate unmatch_reconciliation_record(id, attrs),
    to: Commands.UnmatchReconciliationRecord,
    as: :call

  def unmatch_reconciliation_record(context, id, attrs),
    do: scoped(context, fn -> unmatch_reconciliation_record(id, attrs) end)

  defdelegate create_accounting_export(attrs), to: Commands.CreateAccountingExport, as: :call

  def create_accounting_export(context, attrs),
    do: scoped(context, fn -> create_accounting_export(attrs) end)

  defdelegate update_accounting_export(id, attrs), to: Commands.UpdateAccountingExport, as: :call

  def update_accounting_export(context, id, attrs),
    do: scoped(context, fn -> update_accounting_export(id, attrs) end)

  defdelegate get_accounting_export(id), to: Queries.GetAccountingExport, as: :call
  def get_accounting_export(context, id), do: scoped(context, fn -> get_accounting_export(id) end)

  defdelegate list_accounting_exports(filters), to: Queries.ListAccountingExports, as: :call

  def list_accounting_exports(context, filters),
    do: scoped(context, fn -> list_accounting_exports(filters) end)

  defdelegate accounting_export_rows(range_start, range_end),
    to: Queries.AccountingExportRows,
    as: :call

  def accounting_export_rows(context, range_start, range_end),
    do: scoped(context, fn -> accounting_export_rows(range_start, range_end) end)

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: Palee.Finance.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  # Phase B (ADR-097)
  defdelegate create_freeze(user_id, admin_id, params), to: FinanceStore

  def create_freeze(context, user_id, admin_id, params),
    do: scoped(context, fn -> create_freeze(user_id, admin_id, params) end)

  defdelegate cancel_freeze(user_id, freeze_id, params), to: FinanceStore

  def cancel_freeze(context, user_id, freeze_id, params),
    do: scoped(context, fn -> cancel_freeze(user_id, freeze_id, params) end)

  defdelegate list_freezes(user_id), to: FinanceStore
  def list_freezes(context, user_id), do: scoped(context, fn -> list_freezes(user_id) end)

  defdelegate booking_terms(user_id, occurred_on), to: FinanceStore

  def booking_terms(context, user_id, occurred_on),
    do: scoped(context, fn -> booking_terms(user_id, occurred_on) end)

  @doc """
  Terms of the package that would pay for `allowance` on that day (ADR-098),
  or nil when no held package includes it.
  """
  def allowance_terms(context, user_id, allowance, occurred_on),
    do: scoped(context, fn -> FinanceStore.allowance_terms(user_id, allowance, occurred_on) end)

  # ADR-098 payment models: shared beneficiaries and corporate clients.
  def list_beneficiaries(context, subscription_id),
    do: scoped(context, fn -> FinanceStore.list_beneficiaries(subscription_id) end)

  def add_beneficiary(context, subscription_id, user_id, admin_id, params),
    do:
      scoped(context, fn ->
        FinanceStore.add_beneficiary(subscription_id, user_id, admin_id, params)
      end)

  def remove_beneficiary(context, subscription_id, beneficiary_id),
    do:
      scoped(context, fn -> FinanceStore.remove_beneficiary(subscription_id, beneficiary_id) end)

  def list_corporate_clients(context),
    do: scoped(context, fn -> FinanceStore.list_corporate_clients() end)

  def get_corporate_client(context, id),
    do: scoped(context, fn -> FinanceStore.get_corporate_client(id) end)

  def find_corporate_client(context, criteria),
    do: scoped(context, fn -> FinanceStore.find_corporate_client(criteria) end)

  def create_corporate_client(context, params),
    do: scoped(context, fn -> FinanceStore.create_corporate_client(params) end)

  def update_corporate_client(context, id, params),
    do: scoped(context, fn -> FinanceStore.update_corporate_client(id, params) end)

  def enroll_corporate_seat(context, client_id, user_id, params),
    do: scoped(context, fn -> FinanceStore.enroll_corporate_seat(client_id, user_id, params) end)

  def end_corporate_seat(context, client_id, subscription_id),
    do: scoped(context, fn -> FinanceStore.end_corporate_seat(client_id, subscription_id) end)

  def list_corporate_seats(context, client_id),
    do: scoped(context, fn -> FinanceStore.list_corporate_seats(client_id) end)

  @doc """
  ADR-205: ends the active corporate seats `user_ids` took by their email
  domain whose client's domain no longer matches `email`.
  """
  def end_email_domain_seats(context, user_ids, email),
    do: scoped(context, fn -> FinanceStore.end_email_domain_seats(user_ids, email) end)

  def generate_corporate_invoice(context, client_id, on),
    do: scoped(context, fn -> FinanceStore.generate_corporate_invoice(client_id, on) end)

  def list_corporate_invoices(context, client_id),
    do: scoped(context, fn -> FinanceStore.list_corporate_invoices(client_id) end)

  def set_corporate_invoice_status(context, invoice_id, status),
    do: scoped(context, fn -> FinanceStore.set_corporate_invoice_status(invoice_id, status) end)

  def get_corporate_invoice(context, invoice_id),
    do: scoped(context, fn -> FinanceStore.get_corporate_invoice(invoice_id) end)

  def record_corporate_payment(context, invoice_id, admin_id, params),
    do:
      scoped(context, fn ->
        FinanceStore.record_corporate_payment(invoice_id, admin_id, params)
      end)

  def reverse_corporate_payment(context, invoice_id, payment_id, admin_id, params),
    do:
      scoped(context, fn ->
        FinanceStore.reverse_corporate_payment(invoice_id, payment_id, admin_id, params)
      end)

  def issue_due_corporate_invoices(context, today),
    do: scoped(context, fn -> FinanceStore.issue_due_corporate_invoices(today) end)

  def mark_overdue_corporate_invoices(context, today),
    do: scoped(context, fn -> FinanceStore.mark_overdue_corporate_invoices(today) end)

  def corporate_invoices_needing_reminder(context, today, interval_days),
    do:
      scoped(context, fn ->
        FinanceStore.corporate_invoices_needing_reminder(today, interval_days)
      end)

  def mark_corporate_invoice_reminded(context, invoice_id, on),
    do: scoped(context, fn -> FinanceStore.mark_corporate_invoice_reminded(invoice_id, on) end)

  def subscriptions_due_for_expiry_reminder(context, today),
    do: scoped(context, fn -> FinanceStore.subscriptions_due_for_expiry_reminder(today) end)

  # ── Revenue streams (ADR-190) ───────────────────────────────────────────
  # Money rows of streams other than memberships (the shop), tagged with
  # their `revenue_stream` and source, in the same tables and numbering.

  alias Palee.Finance.Domain.RevenueStream
  alias Palee.Finance.RevenueStreamStore

  defdelegate revenue_streams(), to: RevenueStream, as: :keys

  @doc """
  The buyer's membership id and package member discount on products
  (ADR-097), or nil when the person has no membership here.
  """
  def member_shop_terms(context, user_id),
    do: scoped(context, fn -> FinanceStore.member_shop_terms(user_id) end)

  @doc "An issued invoice with lines, each naming its source row (`source_type`, `source_id`)."
  def record_stream_invoice(context, attrs), do: RevenueStreamStore.record_invoice(context, attrs)

  @doc "The payment of a stream invoice; idempotent per `source_type` / `source_id`."
  def record_stream_payment(context, attrs), do: RevenueStreamStore.record_payment(context, attrs)

  @doc "A refund of a stream payment; the reversal keeps the payment's stream and source."
  def reverse_stream_payment(context, attrs),
    do: RevenueStreamStore.reverse_payment(context, attrs)

  def void_stream_invoice(context, invoice_id, attrs \\ %{}),
    do: RevenueStreamStore.void_invoice(context, invoice_id, attrs)

  @doc "Records the legal receipt reference (myDATA MARK, register receipt) of an invoice."
  def set_fiscal_receipt_ref(context, invoice_id, ref),
    do: RevenueStreamStore.set_fiscal_receipt_ref(context, invoice_id, ref)

  @doc """
  Paid, refunded and net revenue per stream and currency between two dates
  (inclusive). `filters[:user_ids]` narrows to people (ADR-186 §7 branch
  filter).
  """
  def revenue_by_stream(context, %Date{} = from, %Date{} = to, filters \\ %{}) do
    %{payments: payments, reversals: reversals} =
      RevenueStreamStore.stream_rows(context, from, to, filters)

    RevenueStream.totals(payments, reversals)
  end

  @doc "The Finance rows of one source row (lineage drill-down)."
  def revenue_lineage(context, source_type, source_id),
    do: RevenueStreamStore.lineage(context, source_type, source_id)

  @doc "A person's invoices of `stream` with their payments and reversals."
  def stream_invoices_for_user(context, stream, user_id),
    do: RevenueStreamStore.list_for_user(context, stream, user_id)
end
