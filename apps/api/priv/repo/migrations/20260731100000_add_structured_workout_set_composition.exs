defmodule MilosTraining.Repo.Migrations.AddStructuredWorkoutSetComposition do
  use Ecto.Migration

  def change do
    alter table(:workout_exercises) do
      add :item_type, :string, null: false, default: "exercise"
      add :set_prescriptions, {:array, :map}, null: false, default: []
      add :load_progression, :map
      add :alternating_group_id, :binary_id
    end

    alter table(:exercise_variations) do
      add :set_prescriptions, {:array, :map}
      add :load_progression, :map
      add :note, :text
    end

    create constraint(:workout_exercises, :workout_exercises_item_type_check,
             check: "item_type IN ('exercise', 'header')"
           )

    create index(:workout_exercises, [:superset_group_id])
    create index(:workout_exercises, [:alternating_group_id])
  end
end
