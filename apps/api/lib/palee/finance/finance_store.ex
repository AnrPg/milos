defmodule Palee.Finance.FinanceStore do
  @behaviour Palee.Finance.Ports.FinanceStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:palee, :finance_store)
  end

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def create_package(params), do: adapter().create_package(params)
  @impl true
  def update_package(id, params), do: adapter().update_package(id, params)
  @impl true
  def retire_package(id, replacements), do: adapter().retire_package(id, replacements)
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
  def create_receipt(membership_id, params), do: adapter().create_receipt(membership_id, params)
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
  def list_finance_cleanup_records(params), do: adapter().list_finance_cleanup_records(params)
  @impl true
  def soft_delete_finance_record(record_type, record_id, admin_id, params),
    do: adapter().soft_delete_finance_record(record_type, record_id, admin_id, params)

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
  def package_coverage(user_id, requests), do: adapter().package_coverage(user_id, requests)
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
  def revoke_allowance_grant(user_id, admin_id, grant_id, params),
    do: adapter().revoke_allowance_grant(user_id, admin_id, grant_id, params)

  @impl true
  def release_stale_entitlement_reservations(cutoff),
    do: adapter().release_stale_entitlement_reservations(cutoff)

  @impl true
  def transition_entitlement_source(
        user_id,
        source_context,
        source_id,
        allowance,
        transition,
        params
      ),
      do:
        adapter().transition_entitlement_source(
          user_id,
          source_context,
          source_id,
          allowance,
          transition,
          params
        )

  @impl true
  def list_expiring_memberships(days), do: adapter().list_expiring_memberships(days)
  @impl true
  def operational_queues(params), do: adapter().operational_queues(params)
  @impl true
  def financial_summary(params), do: adapter().financial_summary(params)
  @impl true
  def package_location_scopes, do: adapter().package_location_scopes()
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
  def get_active_referral_program, do: adapter().get_active_referral_program()
  @impl true
  def get_referral_program(id), do: adapter().get_referral_program(id)
  @impl true
  def open_attributed_referral(params), do: adapter().open_attributed_referral(params)
  @impl true
  def count_referral_events_since(referrer_user_id, since),
    do: adapter().count_referral_events_since(referrer_user_id, since)

  @impl true
  def referral_outcomes(event_ids), do: adapter().referral_outcomes(event_ids)
  @impl true
  def extend_current_subscription(membership_id, days),
    do: adapter().extend_current_subscription(membership_id, days)

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
  def subscriptions_needing_expiry_notice(kind, days),
    do: adapter().subscriptions_needing_expiry_notice(kind, days)

  @impl true
  def mark_subscription_notice_sent(subscription_id, kind),
    do: adapter().mark_subscription_notice_sent(subscription_id, kind)

  @impl true
  def refresh_entitlement_snapshots, do: adapter().refresh_entitlement_snapshots()

  @impl true
  def total_outstanding_balance_cents, do: adapter().total_outstanding_balance_cents()

  @impl true
  def count_pending_referral_approvals, do: adapter().count_pending_referral_approvals()

  @impl true
  def create_freeze(user_id, admin_id, params),
    do: adapter().create_freeze(user_id, admin_id, params)

  @impl true
  def cancel_freeze(user_id, freeze_id, params),
    do: adapter().cancel_freeze(user_id, freeze_id, params)

  @impl true
  def list_freezes(user_id), do: adapter().list_freezes(user_id)
  @impl true
  def booking_terms(user_id, occurred_on), do: adapter().booking_terms(user_id, occurred_on)

  @impl true
  def allowance_terms(user_id, allowance, occurred_on),
    do: adapter().allowance_terms(user_id, allowance, occurred_on)

  @impl true
  def list_beneficiaries(subscription_id), do: adapter().list_beneficiaries(subscription_id)

  @impl true
  def add_beneficiary(subscription_id, user_id, admin_id, params),
    do: adapter().add_beneficiary(subscription_id, user_id, admin_id, params)

  @impl true
  def remove_beneficiary(subscription_id, beneficiary_id),
    do: adapter().remove_beneficiary(subscription_id, beneficiary_id)

  @impl true
  def list_corporate_clients(), do: adapter().list_corporate_clients()

  @impl true
  def get_corporate_client(id), do: adapter().get_corporate_client(id)

  @impl true
  def find_corporate_client(criteria), do: adapter().find_corporate_client(criteria)

  @impl true
  def create_corporate_client(params), do: adapter().create_corporate_client(params)

  @impl true
  def update_corporate_client(id, params), do: adapter().update_corporate_client(id, params)

  @impl true
  def enroll_corporate_seat(client_id, user_id, params),
    do: adapter().enroll_corporate_seat(client_id, user_id, params)

  @impl true
  def end_corporate_seat(client_id, subscription_id),
    do: adapter().end_corporate_seat(client_id, subscription_id)

  @impl true
  def list_corporate_seats(client_id), do: adapter().list_corporate_seats(client_id)

  @impl true
  def generate_corporate_invoice(client_id, on),
    do: adapter().generate_corporate_invoice(client_id, on)

  @impl true
  def list_corporate_invoices(client_id), do: adapter().list_corporate_invoices(client_id)

  @impl true
  def set_corporate_invoice_status(invoice_id, status),
    do: adapter().set_corporate_invoice_status(invoice_id, status)

  @impl true
  def get_corporate_invoice(id), do: adapter().get_corporate_invoice(id)

  @impl true
  def record_corporate_payment(invoice_id, admin_id, params),
    do: adapter().record_corporate_payment(invoice_id, admin_id, params)

  @impl true
  def reverse_corporate_payment(invoice_id, payment_id, admin_id, params),
    do: adapter().reverse_corporate_payment(invoice_id, payment_id, admin_id, params)

  @impl true
  def issue_due_corporate_invoices(today), do: adapter().issue_due_corporate_invoices(today)

  @impl true
  def mark_overdue_corporate_invoices(today), do: adapter().mark_overdue_corporate_invoices(today)

  @impl true
  def corporate_invoices_needing_reminder(today, interval_days),
    do: adapter().corporate_invoices_needing_reminder(today, interval_days)

  @impl true
  def mark_corporate_invoice_reminded(id, on),
    do: adapter().mark_corporate_invoice_reminded(id, on)

  @impl true
  def subscriptions_due_for_expiry_reminder(today),
    do: adapter().subscriptions_due_for_expiry_reminder(today)
end
