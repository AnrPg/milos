defmodule MilosTraining.Repo.Migrations.CreateWorkoutExercises do
  use Ecto.Migration

  def change do
    create table(:workout_exercises, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workout_section_id,
          references(:workout_sections, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text
      add :base_sets, :integer
      add :base_reps, :integer
      add :base_duration_seconds, :integer
      add :order, :integer, null: false
    end

    create index(:workout_exercises, [:workout_section_id])
    create unique_index(:workout_exercises, [:workout_section_id, :order])
  end
end
