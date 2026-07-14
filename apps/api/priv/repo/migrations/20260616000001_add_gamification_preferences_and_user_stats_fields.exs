defmodule MilosTraining.Repo.Migrations.AddGamificationPreferencesAndUserStatsFields do
  use Ecto.Migration

  def change do
    create table(:user_gamification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :off_days, {:array, :integer}, default: [], null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_gamification_preferences, [:user_id])

    alter table(:user_stats) do
      add :motivation_score, :float, default: 0.0, null: false
      add :perseverance_score, :float, default: 0.0, null: false
      add :advancement_count, :integer, default: 0, null: false
    end

    # current_streak and longest_streak change semantic from weeks to days
    execute "UPDATE user_stats SET current_streak = 0, longest_streak = 0"
  end
end
