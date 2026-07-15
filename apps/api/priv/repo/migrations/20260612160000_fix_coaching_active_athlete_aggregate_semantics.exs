defmodule MilosTraining.Repo.Migrations.FixCoachingActiveAthleteAggregateSemantics do
  use Ecto.Migration

  def up do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      date_trunc('week', timezone('utc', now()))::date AS period_start,
      COUNT(DISTINCT u.id) FILTER (
        WHERE u.role = 'athlete'
          AND EXISTS (
            SELECT 1
            FROM workout_executions we_recent
            WHERE we_recent.user_id = u.id
              AND we_recent.completed_at_utc >= timezone('utc', now()) - interval '14 days'
          )
      )::integer AS active_athlete_count,
      COUNT(DISTINCT u.id) FILTER (
        WHERE u.role = 'athlete'
          AND NOT EXISTS (
            SELECT 1
            FROM workout_executions we_recent
            WHERE we_recent.user_id = u.id
              AND we_recent.completed_at_utc >= timezone('utc', now()) - interval '14 days'
          )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT we.id) FILTER (
        WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
      )::integer AS completed_workouts_this_week,
      COUNT(DISTINCT n.id) FILTER (
        WHERE n.inserted_at >= date_trunc('week', timezone('utc', now()))
      )::integer AS coach_notes_this_week,
      COALESCE(
        (
          COUNT(DISTINCT we.id) FILTER (
            WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
          )::float
          / NULLIF(COUNT(DISTINCT u.id) FILTER (WHERE u.role = 'athlete'), 0)
        ),
        0.0
      ) AS average_completion_rate,
      COUNT(DISTINCT we.id) FILTER (
        WHERE cardinality(we.exercise_notes) > 0
          AND we.completed_at_utc >= timezone('utc', now()) - interval '30 days'
      )::integer AS recent_workout_note_count
    FROM users u
    LEFT JOIN workout_executions we ON we.user_id = u.id
    LEFT JOIN admin_athlete_notes n ON n.athlete_id = u.id
    WITH NO DATA
    """)

    execute("""
    CREATE UNIQUE INDEX coaching_aggregates_period_index
    ON coaching_aggregates (period_start)
    """)
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      date_trunc('week', timezone('utc', now()))::date AS period_start,
      COUNT(DISTINCT u.id) FILTER (WHERE u.role = 'athlete')::integer AS active_athlete_count,
      COUNT(DISTINCT u.id) FILTER (
        WHERE u.role = 'athlete'
          AND NOT EXISTS (
            SELECT 1
            FROM workout_executions we_recent
            WHERE we_recent.user_id = u.id
              AND we_recent.completed_at_utc >= timezone('utc', now()) - interval '14 days'
          )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT we.id) FILTER (
        WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
      )::integer AS completed_workouts_this_week,
      COUNT(DISTINCT n.id) FILTER (
        WHERE n.inserted_at >= date_trunc('week', timezone('utc', now()))
      )::integer AS coach_notes_this_week,
      COALESCE(
        (
          COUNT(DISTINCT we.id) FILTER (
            WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
          )::float
          / NULLIF(COUNT(DISTINCT u.id) FILTER (WHERE u.role = 'athlete'), 0)
        ),
        0.0
      ) AS average_completion_rate,
      COUNT(DISTINCT we.id) FILTER (
        WHERE cardinality(we.exercise_notes) > 0
          AND we.completed_at_utc >= timezone('utc', now()) - interval '30 days'
      )::integer AS recent_workout_note_count
    FROM users u
    LEFT JOIN workout_executions we ON we.user_id = u.id
    LEFT JOIN admin_athlete_notes n ON n.athlete_id = u.id
    WITH NO DATA
    """)

    execute("""
    CREATE UNIQUE INDEX coaching_aggregates_period_index
    ON coaching_aggregates (period_start)
    """)
  end
end
