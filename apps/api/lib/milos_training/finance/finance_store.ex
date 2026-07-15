defmodule MilosTraining.Finance.FinanceStore do
  @behaviour MilosTraining.Finance.Ports.FinanceStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :finance_store,
      MilosTraining.Infrastructure.Finance.EctoFinanceStore
    )
  end

  @impl true
  def create_package(params), do: adapter().create_package(params)
  @impl true
  def update_package(id, params), do: adapter().update_package(id, params)
  @impl true
  def list_packages, do: adapter().list_packages()
  @impl true
  def get_package(id), do: adapter().get_package(id)
  @impl true
  def upsert_membership(user_id, params), do: adapter().upsert_membership(user_id, params)
  @impl true
  def get_member_profile(user_id), do: adapter().get_member_profile(user_id)
  @impl true
  def search_member_summaries(params), do: adapter().search_member_summaries(params)
  @impl true
  def assign_package(membership_id, package_id, params),
    do: adapter().assign_package(membership_id, package_id, params)

  @impl true
  def record_payment(membership_id, params), do: adapter().record_payment(membership_id, params)
  @impl true
  def create_manual_credit(membership_id, params),
    do: adapter().create_manual_credit(membership_id, params)

  @impl true
  def apply_credit_to_payment(membership_id, payment_id, params),
    do: adapter().apply_credit_to_payment(membership_id, payment_id, params)

  @impl true
  def reverse_payment(membership_id, payment_id, params),
    do: adapter().reverse_payment(membership_id, payment_id, params)

  @impl true
  def reverse_credit_ledger_entry(membership_id, entry_id, params),
    do: adapter().reverse_credit_ledger_entry(membership_id, entry_id, params)

  @impl true
  def get_invoice(invoice_id), do: adapter().get_invoice(invoice_id)
  @impl true
  def update_invoice_params(invoice_id, params),
    do: adapter().update_invoice_params(invoice_id, params)

  @impl true
  def update_invoice(invoice_id, params), do: adapter().update_invoice(invoice_id, params)
  @impl true
  def mark_overdue_invoices, do: adapter().mark_overdue_invoices()

  @impl true
  def create_invoice(membership_id, params), do: adapter().create_invoice(membership_id, params)
  @impl true
  def generate_renewal_invoice(membership_id, params),
    do: adapter().generate_renewal_invoice(membership_id, params)

  @impl true
  def issue_invoice(invoice_id, params), do: adapter().issue_invoice(invoice_id, params)
  @impl true
  def void_invoice(invoice_id, params), do: adapter().void_invoice(invoice_id, params)
  @impl true
  def apply_credit_to_invoice(membership_id, invoice_id, params),
    do: adapter().apply_credit_to_invoice(membership_id, invoice_id, params)

  @impl true
  def get_entitlement(user_id), do: adapter().get_entitlement(user_id)
  @impl true
  def get_effective_entitlement(user_id), do: adapter().get_effective_entitlement(user_id)
  @impl true
  def reserve_entitlement(user_id, request), do: adapter().reserve_entitlement(user_id, request)
  @impl true
  def finalize_entitlement(reservation_id, params),
    do: adapter().finalize_entitlement(reservation_id, params)

  @impl true
  def release_entitlement(reservation_id, params),
    do: adapter().release_entitlement(reservation_id, params)

  @impl true
  def grant_allowance(user_id, admin_id, params),
    do: adapter().grant_allowance(user_id, admin_id, params)

  @impl true
  def list_expiring_memberships(days), do: adapter().list_expiring_memberships(days)
  @impl true
  def operational_queues(params), do: adapter().operational_queues(params)
  @impl true
  def financial_summary(params), do: adapter().financial_summary(params)
  @impl true
  def create_promotion_campaign(params), do: adapter().create_promotion_campaign(params)
  @impl true
  def list_promotion_campaigns, do: adapter().list_promotion_campaigns()
  @impl true
  def create_promotion_code(campaign_id, params),
    do: adapter().create_promotion_code(campaign_id, params)

  @impl true
  def list_promotion_codes(campaign_id), do: adapter().list_promotion_codes(campaign_id)
  @impl true
  def redeem_promotion(membership_id, params),
    do: adapter().redeem_promotion(membership_id, params)

  @impl true
  def create_referral_program(params), do: adapter().create_referral_program(params)
  @impl true
  def update_referral_program(id, params), do: adapter().update_referral_program(id, params)
  @impl true
  def list_referral_programs, do: adapter().list_referral_programs()
  @impl true
  def create_referral_event(params), do: adapter().create_referral_event(params)
  @impl true
  def update_referral_status(id, status), do: adapter().update_referral_status(id, status)
  @impl true
  def list_referral_events, do: adapter().list_referral_events()
  @impl true
  def create_referral_reward(referral_event_id, params),
    do: adapter().create_referral_reward(referral_event_id, params)

  @impl true
  def list_referral_rewards, do: adapter().list_referral_rewards()
  @impl true
  def update_referral_reward_status(id, status),
    do: adapter().update_referral_reward_status(id, status)

  @impl true
  def refresh_aggregates, do: adapter().refresh_aggregates()

  @impl true
  def get_finance_settings, do: adapter().get_finance_settings()
  @impl true
  def update_finance_settings(params), do: adapter().update_finance_settings(params)
  @impl true
  def membership_outstanding_balance_cents(membership_id),
    do: adapter().membership_outstanding_balance_cents(membership_id)

  @impl true
  def outstanding_balance_per_membership(membership_ids),
    do: adapter().outstanding_balance_per_membership(membership_ids)

  @impl true
  def invoice_balance_due_map(invoice_ids), do: adapter().invoice_balance_due_map(invoice_ids)

  @impl true
  def update_membership_reminder_timestamp(membership_id),
    do: adapter().update_membership_reminder_timestamp(membership_id)

  @impl true
  def memberships_needing_payment_reminder(interval_days),
    do: adapter().memberships_needing_payment_reminder(interval_days)

  @impl true
  def total_outstanding_balance_cents, do: adapter().total_outstanding_balance_cents()

  @impl true
  def count_pending_referral_approvals, do: adapter().count_pending_referral_approvals()
end
