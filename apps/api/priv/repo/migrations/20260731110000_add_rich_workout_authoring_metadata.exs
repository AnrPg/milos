defmodule MilosTraining.Repo.Migrations.AddRichWorkoutAuthoringMetadata do
  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      add :subtitle, :string
      add :description, :text
      add :difficulty, :string
      add :estimated_duration_seconds, :integer
      add :equipment, {:array, :string}, null: false, default: []
      add :tags, {:array, :string}, null: false, default: []
      add :notes, {:array, :map}, null: false, default: []
      add :workout_metadata, :map, null: false, default: %{}
    end

    alter table(:workout_sections) do
      add :subtitle, :string
      add :rest_before_next_section_seconds, :integer
      add :notes, {:array, :map}, null: false, default: []
      add :section_metadata, :map, null: false, default: %{}
    end

    alter table(:workout_exercises) do
      add :subtitle, :string
      add :exercise_ref, :string
      add :notes, {:array, :map}, null: false, default: []
      add :prescription_metadata, :map, null: false, default: %{}
      add :group_config, :map
    end

    alter table(:exercise_variations) do
      add :notes, {:array, :map}, null: false, default: []
      add :prescription_metadata, :map, null: false, default: %{}
    end

    create index(:workout_exercises, [:exercise_ref])

    create constraint(:master_workouts, :master_workouts_difficulty_check,
             check:
               "difficulty IS NULL OR difficulty IN ('beginner', 'intermediate', 'advanced', 'all-levels')"
           )

    create constraint(:master_workouts, :master_workouts_estimated_duration_check,
             check:
               "estimated_duration_seconds IS NULL OR estimated_duration_seconds BETWEEN 1 AND 86400"
           )

    create constraint(
             :workout_sections,
             :workout_sections_rest_before_next_section_check,
             check:
               "rest_before_next_section_seconds IS NULL OR rest_before_next_section_seconds >= 0"
           )
  end
end
