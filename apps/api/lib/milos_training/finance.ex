defmodule MilosTraining.Finance do
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
    IssueInvoice,
    RecordPayment,
    RedeemPromotion,
    RefreshAggregates,
    ReverseCreditLedgerEntry,
    ReversePayment,
    UpdatePackage,
    UpdateReferralRewardStatus,
    UpdateReferralStatus,
    VoidInvoice,
    UpsertMembership
  }

  alias MilosTraining.Finance.Queries.{
    FinancialSummary,
    GetEntitlement,
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
  defdelegate update_invoice_params(invoice_id, params), to: FinanceStore, as: :update_invoice_params
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
  defdelegate list_expiring_memberships(days), to: ListExpiringMemberships, as: :call
  defdelegate operational_queues(params \\ %{}), to: OperationalQueues, as: :call
  def financial_summary(params \\ %{}), do: FinancialSummary.call(params)
  defdelegate create_promotion_campaign(params), to: CreatePromotionCampaign, as: :call
  defdelegate list_promotion_campaigns(), to: ListPromotionCampaigns, as: :call
  defdelegate create_promotion_code(campaign_id, params), to: CreatePromotionCode, as: :call
  defdelegate list_promotion_codes(campaign_id \\ nil), to: ListPromotionCodes, as: :call
  defdelegate redeem_promotion(membership_id, params), to: RedeemPromotion, as: :call
  defdelegate create_referral_program(params), to: CreateReferralProgram, as: :call
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
end
