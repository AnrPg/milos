defmodule Palee.Repo.Migrations.RemoveStaffFinanceProfiles do
  use Ecto.Migration

  # ADR-217: only clients (a member or athlete role in the gym) have a finance
  # profile. Profiles were created for owners and other staff when someone
  # touched their row in the finance ledger (it listed every person of the gym
  # and showed "trial" for anyone without a profile). Remove the profiles of
  # people who are staff-only in that gym and never moved money: no invoice,
  # payment, reversal, refund, credit or entitlement use. Their package
  # assignments, freezes and promotion rows go with them (ON DELETE CASCADE).
  # A staff-only person with money history keeps the record, since that money
  # is real; they are no longer listed in the ledger. Data only: `down` is a
  # no-op.
  def up, do: execute(cleanup_sql())

  def down, do: :ok

  @doc false
  def cleanup_sql do
    """
    DELETE FROM memberships m
    USING organization_memberships om
    WHERE om.organization_id = m.organization_id
      AND om.user_id = m.user_id
      AND om.status = 'active'
      AND NOT (om.roles::text[] && ARRAY['member', 'athlete']::text[])
      AND NOT EXISTS (SELECT 1 FROM finance_invoices i WHERE i.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM membership_payments p WHERE p.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM finance_payment_reversals r WHERE r.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM finance_refund_receipts rr WHERE rr.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM finance_credit_ledger_entries c WHERE c.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM finance_entitlement_usage_entries u WHERE u.membership_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM referral_rewards rw WHERE rw.membership_id = m.id)
    """
  end
end
