defmodule MilosTraining.Repo.Migrations.CreateGamificationTables do
  use Ecto.Migration

  def up do
    create table(:user_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :current_streak, :integer, null: false, default: 0
      add :longest_streak, :integer, null: false, default: 0
      add :total_workouts, :integer, null: false, default: 0
      add :total_prs, :integer, null: false, default: 0
      add :current_streak_shields, :integer, null: false, default: 1
      add :last_workout_at, :utc_datetime_usec
      add :consistency_score, :float, null: false, default: 0.0
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_stats, [:user_id])

    create table(:user_achievements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :badge_key, :string, null: false
      add :earned_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_achievements, [:user_id, :badge_key])
    create index(:user_achievements, [:user_id, :earned_at])

    create table(:seasonal_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :criteria_type, :string, null: false
      add :criteria_value, :map, null: false, default: %{}
      add :badge_key, :string, null: false
      add :badge_label, :string, null: false
      add :starts_at, :date, null: false
      add :ends_at, :date, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:seasonal_challenges, [:starts_at, :ends_at])

    create constraint(
             :seasonal_challenges,
             :seasonal_challenges_criteria_type_check,
             check:
               "criteria_type in ('workout_count', 'workout_type_count', 'pr_count', 'custom')"
           )

    create table(:user_challenge_progress, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :challenge_id,
          references(:seasonal_challenges, type: :binary_id, on_delete: :delete_all),
          null: false

      add :progress, :integer, null: false, default: 0
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_challenge_progress, [:user_id, :challenge_id])
    create index(:user_challenge_progress, [:challenge_id, :completed_at])

    create table(:leaderboard_opt_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :opted_in_at, :utc_datetime_usec, null: false
    end

    create unique_index(:leaderboard_opt_ins, [:user_id])

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

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS weekly_leaderboard")
    drop table(:leaderboard_opt_ins)
    drop table(:user_challenge_progress)
    drop constraint(:seasonal_challenges, :seasonal_challenges_criteria_type_check)
    drop table(:seasonal_challenges)
    drop table(:user_achievements)
    drop table(:user_stats)
  end
end
