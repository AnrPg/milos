defmodule MilosTraining.Repo.Migrations.ScopeCoachingProjectionsToOrganizations do
  use Ecto.Migration

  def up do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      membership.organization_id,
      date_trunc('week', timezone('utc', NOW()))::date AS period_start,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS active_athlete_count,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE NOT EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT execution.id) FILTER (
        WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS completed_workouts_this_week,
      COUNT(DISTINCT message.id) FILTER (
        WHERE message.inserted_at >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS coach_notes_this_week,
      COALESCE(
        COUNT(DISTINCT execution.id) FILTER (
          WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
        )::float / NULLIF(COUNT(DISTINCT membership.user_id), 0)::float,
        0.0
      ) AS average_completion_rate,
      COUNT(DISTINCT execution.id) FILTER (
        WHERE cardinality(execution.exercise_notes) > 0
          AND execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '30 days'
      )::integer AS recent_workout_note_count
    FROM organization_memberships membership
    JOIN organizations organization ON organization.id = membership.organization_id
    LEFT JOIN workout_executions execution
      ON execution.user_id = membership.user_id
      AND execution.organization_id = membership.organization_id
    LEFT JOIN messaging_messages message
      ON message.organization_id = membership.organization_id
      AND message.message_type = 'coaching_note'
    WHERE membership.status = 'active'
      AND membership.role = 'athlete'
      AND organization.status = 'active'
    GROUP BY membership.organization_id
    """)

    execute("""
    CREATE UNIQUE INDEX coaching_aggregates_organization_period_index
    ON coaching_aggregates (organization_id, period_start)
    """)

    execute("DROP POLICY IF EXISTS workout_executions_owner_policy ON workout_executions")

    execute("""
    CREATE POLICY workout_executions_owner_or_tenant_policy ON workout_executions
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end

  def down do
    execute(
      "DROP POLICY IF EXISTS workout_executions_owner_or_tenant_policy ON workout_executions"
    )

    execute("""
    CREATE POLICY workout_executions_owner_policy ON workout_executions
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")
  end
end
