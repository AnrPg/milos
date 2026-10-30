defmodule Palee.Repo.Migrations.InjuriesSharedWithBox do
  @moduledoc """
  ADR-286: injuries a member records in the app reach their boxes, one
  switch per injury («Να το δει το box μου», on by default), and every staff
  read is logged.

  A member's own injury report is account-scoped (`organization_id` NULL):
  it was readable only by the member, so no box ever saw it.

  - `injury_reports.shared_with_box`: the member's choice for that report.
    Existing reports become shared: the app told members their coach always
    sees injuries.
  - `palee_injury_reaches_acting_staff(member_id)`: the session is a gym
    where the acting user is owner, admin or coach (the roles holding
    `view_health`) and the member is an active client there (member or
    athlete). A coach's narrower scope (their own clients, ADR-100) is the
    application's.
  - Read-only policies let such staff see the member's shared, user-visible
    reports and their timelines; writes stay the member's.
  - `injury_access_log`: one row per staff read (who, whose, which reports,
    where), like `body_access_log`; the member reads their own rows and the
    gym's rows go with the gym.
  """

  use Ecto.Migration

  def up do
    alter table(:injury_reports) do
      add :shared_with_box, :boolean, null: false, default: true
    end

    execute("""
    CREATE FUNCTION palee_injury_reaches_acting_staff(member_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT NULLIF(current_setting('app.organization_id', true), '') IS NOT NULL
        AND member_id IS DISTINCT FROM NULLIF(current_setting('app.user_id', true), '')::uuid
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships staff
          WHERE staff.organization_id =
                  NULLIF(current_setting('app.organization_id', true), '')::uuid
            AND staff.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            AND staff.status = 'active'
            AND staff.roles::text[] && ARRAY['owner', 'admin', 'coach']::text[]
        )
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships target
          WHERE target.organization_id =
                  NULLIF(current_setting('app.organization_id', true), '')::uuid
            AND target.user_id = member_id
            AND target.status = 'active'
            AND target.roles::text[] && ARRAY['member', 'athlete']::text[]
        )
    $$
    """)

    execute("""
    CREATE POLICY injury_reports_shared_with_box_read_policy ON injury_reports
    FOR SELECT
    USING (
      organization_id IS NULL
      AND visibility = 'user_and_admin'
      AND shared_with_box
      AND palee_injury_reaches_acting_staff(user_id)
    )
    """)

    # Events follow their report, whose own policies apply inside EXISTS.
    execute("""
    CREATE POLICY injury_status_events_shared_with_box_read_policy ON injury_status_events
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM injury_reports r
        WHERE r.id = injury_status_events.injury_report_id
          AND r.organization_id IS NULL
      )
    )
    """)

    create table(:injury_access_log, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reader_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :surface, :string, null: false
      add :injury_ids, {:array, :binary_id}, null: false, default: []
      add :read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:injury_access_log, :injury_access_log_surface_check,
             check: "surface IN ('profile', 'box_list', 'safety_warning')"
           )

    create index(:injury_access_log, [:user_id, :read_at])
    create index(:injury_access_log, [:organization_id, :read_at])

    execute("""
    CREATE TRIGGER injury_access_log_apply_tenant_context
    BEFORE INSERT OR UPDATE ON injury_access_log
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY injury_access_log_tenant_policy ON injury_access_log
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY injury_access_log_owner_read_policy ON injury_access_log
    FOR SELECT
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE injury_access_log ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE injury_access_log FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:injury_access_log)

    execute(
      "DROP POLICY IF EXISTS injury_status_events_shared_with_box_read_policy ON injury_status_events"
    )

    execute("DROP POLICY IF EXISTS injury_reports_shared_with_box_read_policy ON injury_reports")
    execute("DROP FUNCTION IF EXISTS palee_injury_reaches_acting_staff(uuid)")

    alter table(:injury_reports) do
      remove :shared_with_box
    end
  end
end
