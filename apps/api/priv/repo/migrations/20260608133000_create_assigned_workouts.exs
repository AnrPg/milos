defmodule MilosTraining.Repo.Migrations.CreateAssignedWorkouts do
  use Ecto.Migration

  def change do
    create table(:assigned_workouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :scheduled_for, :date, null: false
      add :admin_notes, :text

      timestamps(updated_at: false)
    end

    create index(:assigned_workouts, [:master_workout_id])
    create index(:assigned_workouts, [:scheduled_for])

    create table(:assigned_workout_athletes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :assigned_workout_id,
          references(:assigned_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :athlete_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create index(:assigned_workout_athletes, [:athlete_id])
    create unique_index(:assigned_workout_athletes, [:assigned_workout_id, :athlete_id])
  end
end
