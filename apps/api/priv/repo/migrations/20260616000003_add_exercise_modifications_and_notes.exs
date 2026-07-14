defmodule MilosTraining.Repo.Migrations.AddExerciseModificationsAndNotes do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add :exercise_modifications, {:array, :map}, default: [], null: false
    end

    alter table(:workout_sections) do
      add :note, :text
    end

    alter table(:workout_exercises) do
      add :note, :text
    end
  end
end
