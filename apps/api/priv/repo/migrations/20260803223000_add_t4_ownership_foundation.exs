defmodule MilosTraining.Repo.Migrations.AddT4OwnershipFoundation do
  use Ecto.Migration

  @tenant_tables ~w(
    class_types
    scheduling_settings
    class_series
    scheduled_classes
    bookings
    class_attendance_records
    master_workouts
    workout_folders
    workout_sections
    workout_exercises
    exercise_variations
    assigned_workouts
    assigned_workout_athletes
    membership_packages
    memberships
    membership_package_subscriptions
    membership_payments
    promotion_campaigns
    promotion_codes
    promotion_redemptions
    referral_programs
    referral_events
    referral_rewards
    finance_invoices
    finance_invoice_lines
    finance_payment_reversals
    finance_credit_ledger_entries
    finance_entitlement_usage_entries
    finance_settings
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
    review_questionnaires
    reviews
    review_answers
  )a

  @personal_tables ~w(
    workout_executions
    execution_progress_operations
    user_pr_records
    user_stats
    user_achievements
    user_gamification_preferences
    push_subscriptions
    notifications
  )a

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_legacy_organization_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    AS $$
      SELECT id FROM organizations WHERE slug = 'legacy-milos-training' LIMIT 1
    $$
    """)

    execute("""
    INSERT INTO organizations (id, slug, name, status, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'legacy-milos-training',
      'Milos Training',
      'active',
      timezone('utc', now()),
      timezone('utc', now())
    )
    ON CONFLICT (slug) DO NOTHING
    """)

    execute("""
    INSERT INTO organization_settings (
      id,
      organization_id,
      timezone,
      default_locale,
      invitation_lifetime_seconds,
      settings,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      organizations.id,
      'UTC',
      'en',
      604800,
      '{}'::jsonb,
      timezone('utc', now()),
      timezone('utc', now())
    FROM organizations
    WHERE organizations.slug = 'legacy-milos-training'
    ON CONFLICT (organization_id) DO NOTHING
    """)

    execute("""
    INSERT INTO organization_memberships (
      id,
      organization_id,
      user_id,
      role,
      status,
      joined_at,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      organizations.id,
      users.id,
      CASE users.role
        WHEN 'admin' THEN 'owner'
        WHEN 'athlete' THEN 'athlete'
        ELSE 'member'
      END,
      'active',
      timezone('utc', now()),
      timezone('utc', now()),
      timezone('utc', now())
    FROM users
    CROSS JOIN organizations
    WHERE organizations.slug = 'legacy-milos-training'
    ON CONFLICT (organization_id, user_id) DO NOTHING
    """)

    Enum.each(@tenant_tables, &add_tenant_ownership/1)
    Enum.each(@personal_tables, &add_personal_policy/1)

    execute("""
    CREATE POLICY user_pr_history_owner_policy ON user_pr_history
    USING (
      EXISTS (
        SELECT 1
        FROM user_pr_records
        WHERE user_pr_records.id = user_pr_history.pr_record_id
          AND user_pr_records.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
    )
    WITH CHECK (
      EXISTS (
        SELECT 1
        FROM user_pr_records
        WHERE user_pr_records.id = user_pr_history.pr_record_id
          AND user_pr_records.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
    )
    """)

    Enum.each(~w(workout_executions user_pr_records user_pr_history notifications), fn table ->
      execute("""
      ALTER TABLE #{table}
      ADD COLUMN organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT
      """)

      execute("CREATE INDEX #{table}_organization_id_index ON #{table} (organization_id)")
    end)

    execute("""
    ALTER TABLE injury_reports
    ADD COLUMN organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT
    """)

    execute("""
    UPDATE injury_reports
    SET organization_id = milos_legacy_organization_id()
    WHERE reported_by_role = 'admin'
    """)

    execute(
      "CREATE INDEX injury_reports_organization_id_index ON injury_reports (organization_id)"
    )

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

    execute("""
    CREATE POLICY users_owner_policy ON users
    USING (id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS users_owner_policy ON users")
    execute("DROP POLICY IF EXISTS injury_reports_owner_or_tenant_policy ON injury_reports")
    execute("DROP INDEX IF EXISTS injury_reports_organization_id_index")
    execute("ALTER TABLE injury_reports DROP COLUMN IF EXISTS organization_id")

    Enum.each(~w(workout_executions user_pr_records user_pr_history notifications), fn table ->
      execute("DROP INDEX IF EXISTS #{table}_organization_id_index")
      execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS organization_id")
    end)

    Enum.each(@personal_tables, fn table ->
      execute("DROP POLICY IF EXISTS #{table}_owner_policy ON #{table}")
    end)

    execute("DROP POLICY IF EXISTS user_pr_history_owner_policy ON user_pr_history")

    Enum.each(Enum.reverse(@tenant_tables), fn table ->
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")
      execute("DROP INDEX IF EXISTS #{table}_organization_id_index")
      execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS organization_id")
    end)

    execute("DROP FUNCTION IF EXISTS milos_legacy_organization_id()")
  end

  defp add_tenant_ownership(table) do
    execute("""
    ALTER TABLE #{table}
    ADD COLUMN organization_id uuid NOT NULL
      DEFAULT milos_legacy_organization_id()
      REFERENCES organizations(id) ON DELETE RESTRICT
    """)

    execute("CREATE INDEX #{table}_organization_id_index ON #{table} (organization_id)")

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)
  end

  defp add_personal_policy(table) do
    execute("""
    CREATE POLICY #{table}_owner_policy ON #{table}
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end
end
