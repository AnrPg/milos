defmodule MilosTraining.Repo.Migrations.FinalizeRemainingT4TenantBoundaries do
  use Ecto.Migration

  @remaining_tenant_tables ~w(
    messaging_threads
    messaging_participants
    messaging_messages
    seasonal_challenges
    user_challenge_progress
    challenge_leaderboard_opt_ins
    leaderboard_opt_ins
    gamification_settings
    attendance_records
    communication_threads
    communication_messages
    analytics_events
    notification_click_events
    push_dispatch_attempts
  )

  def up do
    Enum.each(@remaining_tenant_tables, fn table ->
      execute("DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}")

      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
      """)

      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      WITH CHECK (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end)
  end

  def down do
    Enum.each(@remaining_tenant_tables, fn table ->
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")
      execute("DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}")
    end)
  end
end
