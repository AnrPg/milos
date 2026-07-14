defmodule MilosTraining.Repo.Migrations.FixWeeklyLeaderboardAggregation do
  use Ecto.Migration

  def up do
    execute("DROP MATERIALIZED VIEW IF EXISTS weekly_leaderboard")

    execute("""
    CREATE MATERIALIZED VIEW weekly_leaderboard AS
    WITH opted_in_users AS (
      SELECT u.id AS user_id, u.nickname
      FROM users u
      JOIN leaderboard_opt_ins lo ON lo.user_id = u.id
    ),
    weekly_workouts AS (
      SELECT
        we.user_id,
        COUNT(*)::integer AS workouts_this_week
      FROM workout_executions we
      WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
      GROUP BY we.user_id
    ),
    monthly_prs AS (
      SELECT
        ua.user_id,
        COUNT(*)::integer AS prs_this_month
      FROM user_achievements ua
      WHERE ua.earned_at >= date_trunc('month', timezone('utc', now()))
        AND ua.badge_key LIKE 'pr_event:%'
      GROUP BY ua.user_id
    )
    SELECT
      users.user_id,
      users.nickname,
      COALESCE(workouts.workouts_this_week, 0) AS workouts_this_week,
      COALESCE(prs.prs_this_month, 0) AS prs_this_month
    FROM opted_in_users users
    LEFT JOIN weekly_workouts workouts ON workouts.user_id = users.user_id
    LEFT JOIN monthly_prs prs ON prs.user_id = users.user_id
    WITH NO DATA
    """)

    execute(
      "CREATE UNIQUE INDEX weekly_leaderboard_user_id_index ON weekly_leaderboard (user_id)"
    )

    execute("REFRESH MATERIALIZED VIEW weekly_leaderboard")
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS weekly_leaderboard")

    execute("""
    CREATE MATERIALIZED VIEW weekly_leaderboard AS
    SELECT
      u.id AS user_id,
      u.nickname,
      COUNT(we.id) FILTER (
        WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
      )::integer AS workouts_this_week,
      COUNT(ua.id) FILTER (
        WHERE ua.earned_at >= date_trunc('month', timezone('utc', now()))
          AND ua.badge_key LIKE 'pr_event:%'
      )::integer AS prs_this_month
    FROM users u
    JOIN leaderboard_opt_ins lo ON lo.user_id = u.id
    LEFT JOIN workout_executions we ON we.user_id = u.id
    LEFT JOIN user_achievements ua ON ua.user_id = u.id
    GROUP BY u.id, u.nickname
    WITH NO DATA
    """)

    execute(
      "CREATE UNIQUE INDEX weekly_leaderboard_user_id_index ON weekly_leaderboard (user_id)"
    )

    execute("REFRESH MATERIALIZED VIEW weekly_leaderboard")
  end
end
