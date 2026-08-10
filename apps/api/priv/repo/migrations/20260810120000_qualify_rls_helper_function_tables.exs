defmodule MilosTraining.Repo.Migrations.QualifyRlsHelperFunctionTables do
  use Ecto.Migration

  # Same bug as 20260806050000 (milos_legacy_organization_id), a second
  # time: milos_acting_user_is_vendor/0, milos_acting_user_belongs_to/1, and
  # milos_acting_user_administers/1 (added in 20260807050000) all read their
  # table (`vendors`, `organization_memberships`) unqualified. That resolves
  # fine for an ordinary SELECT, but these STABLE SQL functions get inlined
  # into the RLS policies of every table that calls them, and CREATE/REFRESH
  # MATERIALIZED VIEW resolves an inlined, unqualified reference differently
  # than plain execution does - failing with `relation "vendors" does not
  # exist` (confirmed live in prod: MilosTraining.Workers.RefreshLeaderboardJob
  # was discarding after 3 attempts on exactly this error, every 15 minutes,
  # per its cron schedule).
  #
  # Unlike 20260806050000, this doesn't need careful placement relative to
  # any specific migration - RefreshLeaderboardJob (and any other cron job
  # touching a materialized view guarded by these policies) re-runs on its
  # own schedule, so fixing the functions here is enough; nothing needs to
  # be "not yet failed" for the fix to take effect.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_is_vendor() RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.vendors v
        WHERE v.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid AND v.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_belongs_to(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_administers(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND om.role IN ('owner', 'admin')
      )
    $$ LANGUAGE sql STABLE;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_is_vendor() RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM vendors v
        WHERE v.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid AND v.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_belongs_to(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_administers(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND om.role IN ('owner', 'admin')
      )
    $$ LANGUAGE sql STABLE;
    """)
  end
end
