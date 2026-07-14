defmodule MilosTraining.Repo.Migrations.CreateGamificationSettings do
  use Ecto.Migration

  def up do
    create table(:gamification_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :weekly_workout_target, :integer, null: false, default: 2
      add :streak_shield_reset_day, :integer
      add :leaderboard_enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :gamification_settings,
             :gamification_settings_weekly_workout_target_check,
             check: "weekly_workout_target > 0"
           )

    create constraint(
             :gamification_settings,
             :gamification_settings_streak_shield_reset_day_check,
             check:
               "streak_shield_reset_day IS NULL OR (streak_shield_reset_day >= 1 AND streak_shield_reset_day <= 28)"
           )
  end

  def down do
    drop table(:gamification_settings)
  end
end
