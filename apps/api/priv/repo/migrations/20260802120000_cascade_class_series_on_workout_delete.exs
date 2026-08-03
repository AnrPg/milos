defmodule MilosTraining.Repo.Migrations.CascadeClassSeriesOnWorkoutDelete do
  use Ecto.Migration

  def up do
    drop constraint(:class_series, "class_series_master_workout_id_fkey")

    alter table(:class_series) do
      modify :master_workout_id,
             references(:master_workouts, type: :binary_id, on_delete: :delete_all),
             null: false
    end
  end

  def down do
    drop constraint(:class_series, "class_series_master_workout_id_fkey")

    alter table(:class_series) do
      modify :master_workout_id,
             references(:master_workouts, type: :binary_id),
             null: false
    end
  end
end
