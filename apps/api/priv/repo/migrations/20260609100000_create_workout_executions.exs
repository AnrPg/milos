defmodule MilosTraining.Repo.Migrations.CreateWorkoutExecutions do
  use Ecto.Migration

  def change do
    create table(:workout_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # nullable — workout may be deleted after execution
      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)

      add :scale_level_slug, :string
      add :source, :string, null: false, default: "self_selected"
      add :started_at_utc, :utc_datetime_usec, null: false
      add :started_at_tz, :string, null: false, default: "UTC"
      add :completed_at_utc, :utc_datetime_usec
      add :completed_at_tz, :string
      add :section_scores, {:array, :map}, null: false, default: []
      add :exercise_notes, {:array, :map}, null: false, default: []

      timestamps(updated_at: false)
    end

    create index(:workout_executions, [:user_id])
    create index(:workout_executions, [:master_workout_id])
    # for workout history timeline queries (most-recent-first per user)
    create index(:workout_executions, [:user_id, :completed_at_utc])
  end
end
