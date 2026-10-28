defmodule Palee.Repo.Migrations.AccountDeletions do
  @moduledoc """
  ADR-211: self-service account deletion.

  - `account_deletions`: one open request per login, for one profile
    (`scope = 'profile'`, `user_id` set) or for the login with all its
    profiles (`scope = 'login'`). It waits for the emailed confirmation
    (`awaiting_confirmation`), then for the 7-day grace (`scheduled`). The
    row goes with the login, or is deleted once the deletion ran; a
    cancelled request is deleted too, so no history of personal data stays.
    A platform table, like `logins`: written by the person's own requests
    and the sweep job, never read by a tenant session, so no RLS.
  - `palee_sole_owned_organizations(user_ids)`: the active businesses where
    one of these profiles is the only active owner (deletion must wait for
    a transfer or closure). A definer function because memberships are a
    tenant table the person's session sees only partly and the sweep job not
    at all.
  - `palee_user_has_retained_records(user_id)`: whether the profile appears
    in accounting records the business must keep (ADR-117's finance
    retention: memberships, invoices, ledger entries, reversals, refund
    receipts). Those cascade from `users`, so such a profile is anonymised
    in place instead of deleted.
  """
  use Ecto.Migration

  def up do
    create table(:account_deletions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :scope, :string, null: false
      add :status, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :scheduled_for, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_deletions, [:login_id])
    create index(:account_deletions, [:scheduled_for], where: "status = 'scheduled'")

    create constraint(:account_deletions, :account_deletions_scope,
             check:
               "(scope = 'profile' AND user_id IS NOT NULL) OR (scope = 'login' AND user_id IS NULL)"
           )

    create constraint(:account_deletions, :account_deletions_status,
             check:
               "(status = 'awaiting_confirmation' AND scheduled_for IS NULL) OR (status = 'scheduled' AND scheduled_for IS NOT NULL)"
           )

    execute("""
    CREATE FUNCTION palee_sole_owned_organizations(p_user_ids uuid[])
    RETURNS TABLE (organization_id uuid, organization_name text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT o.id, o.name::text
      FROM public.organization_memberships m
      JOIN public.organizations o ON o.id = m.organization_id
      WHERE m.user_id = ANY (p_user_ids)
        AND m.status = 'active'
        AND o.status = 'active'
        AND (m.role = 'owner' OR 'owner' = ANY (m.roles))
        AND NOT EXISTS (
          SELECT 1 FROM public.organization_memberships other
          WHERE other.organization_id = m.organization_id
            AND other.status = 'active'
            AND NOT (other.user_id = ANY (p_user_ids))
            AND (other.role = 'owner' OR 'owner' = ANY (other.roles))
        )
    $$
    """)

    execute("""
    CREATE FUNCTION palee_user_has_retained_records(p_user_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (SELECT 1 FROM public.memberships WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_invoices WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_credit_ledger_entries WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_payment_reversals WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_refund_receipts WHERE user_id = p_user_id)
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_user_has_retained_records(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_sole_owned_organizations(uuid[])")
    drop table(:account_deletions)
  end
end
