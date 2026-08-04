defmodule MilosTraining.Repo.Migrations.FinalizePersonalAndWellbeingT4Boundaries do
  use Ecto.Migration

  @personal_tables ~w(
    notifications
    push_subscriptions
    user_pr_records
    user_stats
    user_achievements
    user_gamification_preferences
  )

  def up do
    Enum.each(@personal_tables, fn table ->
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end)

    execute("ALTER TABLE user_pr_history ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE user_pr_history FORCE ROW LEVEL SECURITY")

    execute("DROP POLICY IF EXISTS injury_reports_owner_or_tenant_policy ON injury_reports")

    execute("""
    CREATE POLICY injury_reports_owner_or_tenant_policy ON injury_reports
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    WITH CHECK (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    """)

    execute("ALTER TABLE injury_reports ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE injury_reports FORCE ROW LEVEL SECURITY")

    execute(
      "DROP POLICY IF EXISTS injury_status_events_owner_or_tenant_policy ON injury_status_events"
    )

    execute("""
    CREATE POLICY injury_status_events_owner_or_tenant_policy ON injury_status_events
    USING (
      EXISTS (
        SELECT 1
        FROM injury_reports
        WHERE injury_reports.id = injury_status_events.injury_report_id
          AND (
            injury_reports.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            OR injury_reports.organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
          )
      )
    )
    WITH CHECK (
      EXISTS (
        SELECT 1
        FROM injury_reports
        WHERE injury_reports.id = injury_status_events.injury_report_id
          AND (
            injury_reports.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            OR injury_reports.organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
          )
      )
    )
    """)

    execute("ALTER TABLE injury_status_events ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE injury_status_events FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("ALTER TABLE injury_status_events NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE injury_status_events DISABLE ROW LEVEL SECURITY")

    execute(
      "DROP POLICY IF EXISTS injury_status_events_owner_or_tenant_policy ON injury_status_events"
    )

    execute("ALTER TABLE injury_reports NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE injury_reports DISABLE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS injury_reports_owner_or_tenant_policy ON injury_reports")

    execute("""
    CREATE POLICY injury_reports_owner_or_tenant_policy ON injury_reports
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    WITH CHECK (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    """)

    execute("ALTER TABLE user_pr_history NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE user_pr_history DISABLE ROW LEVEL SECURITY")

    Enum.each(@personal_tables, fn table ->
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
    end)
  end
end
