defmodule MilosTraining.Repo.Migrations.QualifyLegacyOrganizationIdFunction do
  use Ecto.Migration

  # `milos_legacy_organization_id()` (added in 20260803223000) reads
  # `organizations` unqualified. That resolves fine for an ordinary SELECT via
  # the caller's search_path, but every RLS-protected table it backstops
  # (memberships, membership_payments, finance_credit_ledger_entries, etc. -
  # via `COALESCE(current_setting('app.organization_id'), milos_legacy_organization_id())`)
  # gets this function *inlined* into its policy predicate. CREATE MATERIALIZED
  # VIEW's rewrite/planning pass resolves that inlined, unqualified
  # `organizations` reference differently than a plain SELECT does, and fails
  # with `relation "organizations" does not exist` - even though the same role
  # can SELECT the table directly outside a materialized view. Confirmed by
  # reproducing against the live prod database: a plain SELECT of the exact
  # same query succeeds, while wrapping it in CREATE MATERIALIZED VIEW fails,
  # and schema-qualifying the function body resolves it.
  #
  # This was blocking every deploy since 20260806100000 first shipped: three
  # migrations in the 08-06 batch (...100000 scope_finance_aggregates,
  # ...110000 scope_weekly_leaderboard, ...140000 scope_weekly_leaderboard_prs)
  # each CREATE MATERIALIZED VIEW over one of these RLS-protected tables, so
  # the prod migrator has been crash-looping on the first of them for days.
  # Placed at 05:00 - between the function's original definition (08-03) and
  # the first materialized view that depends on it (08-06 10:00) - so it fixes
  # the function before anything needs it, without touching migrations that
  # already ran successfully elsewhere.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_legacy_organization_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    AS $$
      SELECT id FROM public.organizations WHERE slug = 'legacy-milos-training' LIMIT 1
    $$
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION milos_legacy_organization_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    AS $$
      SELECT id FROM organizations WHERE slug = 'legacy-milos-training' LIMIT 1
    $$
    """)
  end
end
