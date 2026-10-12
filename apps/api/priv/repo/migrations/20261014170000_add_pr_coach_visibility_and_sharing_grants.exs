defmodule MilosTraining.Repo.Migrations.AddPrCoachVisibilityAndSharingGrants do
  use Ecto.Migration

  # ADR-111 / TD-062: Pantheon PRs stay user-owned (ADR-055), but become
  # readable by
  #   (a) every coach of the gym the PR was recorded in (organization
  #       provenance), while the owner holds an active membership there and has
  #       not opted out of coach visibility, inside that gym's tenant scope;
  #   (b) every account the owner explicitly granted read access to, regardless
  #       of gym, until the grant is revoked.
  #
  # Both are additional permissive SELECT policies: writes stay owner-only
  # under the existing `*_owner_policy` policies.
  #
  # `milos_acting_user_coaches/1` is the single seam deciding "is the session
  # user a coach of org X". Under today's single-role memberships that is
  # `om.role = 'coach'`. Once memberships carry a role set, only that one
  # predicate line changes (to `'coach' = ANY (om.roles)`); coach_scope and
  # coaching relationships must NOT narrow PR visibility (ADR-111).
  def up do
    create table(:user_pr_sharing_preferences, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :coach_visibility, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create table(:user_pr_share_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :grantee_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create constraint(:user_pr_share_grants, :user_pr_share_grants_not_self,
             check: "user_id <> grantee_user_id"
           )

    create unique_index(:user_pr_share_grants, [:user_id, :grantee_user_id],
             name: :user_pr_share_grants_active_index,
             where: "revoked_at IS NULL"
           )

    create index(:user_pr_share_grants, [:grantee_user_id],
             name: :user_pr_share_grants_grantee_active_index,
             where: "revoked_at IS NULL"
           )

    execute("""
    CREATE POLICY user_pr_sharing_preferences_owner_policy ON user_pr_sharing_preferences
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY user_pr_share_grants_owner_policy ON user_pr_share_grants
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY user_pr_share_grants_grantee_read_policy ON user_pr_share_grants
    FOR SELECT
    USING (grantee_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    Enum.each(~w(user_pr_sharing_preferences user_pr_share_grants), fn table ->
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_coaches(org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1
        FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND om.role = 'coach'
      )
    $$
    """)

    # The owner's membership and opt-out are invisible to the coach's session
    # (memberships admit only self/owner/admin; preferences are owner-only), so
    # this check needs SECURITY DEFINER. It answers one boolean about one PR
    # and only for the gym the session is currently scoped to.
    execute("""
    CREATE OR REPLACE FUNCTION milos_pr_visible_to_acting_coach(pr_user_id uuid, pr_org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT pr_org_id IS NOT NULL
        AND pr_org_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
        AND public.milos_acting_user_coaches(pr_org_id)
        AND EXISTS (
          SELECT 1
          FROM public.organization_memberships target
          WHERE target.organization_id = pr_org_id
            AND target.user_id = pr_user_id
            AND target.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.user_pr_sharing_preferences pref
          WHERE pref.user_id = pr_user_id
            AND pref.coach_visibility = false
        )
    $$
    """)

    execute("""
    CREATE POLICY user_pr_records_coach_read_policy ON user_pr_records
    FOR SELECT
    USING (milos_pr_visible_to_acting_coach(user_id, organization_id))
    """)

    execute("""
    CREATE POLICY user_pr_records_grantee_read_policy ON user_pr_records
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.user_pr_share_grants grants
        WHERE grants.user_id = user_pr_records.user_id
          AND grants.grantee_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND grants.revoked_at IS NULL
      )
    )
    """)

    # History follows its record: visible exactly when the session can see the
    # parent PR under any user_pr_records policy (owner, coach, or grantee).
    execute("""
    CREATE POLICY user_pr_history_shared_read_policy ON user_pr_history
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.user_pr_records records
        WHERE records.id = user_pr_history.pr_record_id
      )
    )
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS user_pr_history_shared_read_policy ON user_pr_history")
    execute("DROP POLICY IF EXISTS user_pr_records_grantee_read_policy ON user_pr_records")
    execute("DROP POLICY IF EXISTS user_pr_records_coach_read_policy ON user_pr_records")
    execute("DROP FUNCTION IF EXISTS milos_pr_visible_to_acting_coach(uuid, uuid)")
    execute("DROP FUNCTION IF EXISTS milos_acting_user_coaches(uuid)")
    drop table(:user_pr_share_grants)
    drop table(:user_pr_sharing_preferences)
  end
end
