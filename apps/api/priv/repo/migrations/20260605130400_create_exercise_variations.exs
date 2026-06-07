defmodule MilosTraining.Repo.Migrations.CreateExerciseVariations do
  use Ecto.Migration

  def change do
    create table(:exercise_variations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workout_exercise_id,
          references(:workout_exercises, type: :binary_id, on_delete: :delete_all),
          null: false

      add :scale_level_id, references(:scale_levels, type: :binary_id, on_delete: :restrict),
        null: false

      add :description, :text
      add :sets, :integer
      add :reps, :integer
      add :duration_seconds, :integer

      timestamps(updated_at: false)
    end

    create index(:exercise_variations, [:workout_exercise_id])
    create index(:exercise_variations, [:scale_level_id])
    create unique_index(:exercise_variations, [:workout_exercise_id, :scale_level_id])
  end
end
