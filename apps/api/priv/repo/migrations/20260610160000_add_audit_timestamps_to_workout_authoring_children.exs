defmodule MilosTraining.Repo.Migrations.AddAuditTimestampsToWorkoutAuthoringChildren do
  use Ecto.Migration

  def up do
    alter table(:workout_sections) do
      add :updated_at, :naive_datetime
    end

    alter table(:workout_exercises) do
      add :inserted_at, :naive_datetime
      add :updated_at, :naive_datetime
    end

    alter table(:exercise_variations) do
      add :updated_at, :naive_datetime
    end

    execute("""
    UPDATE workout_sections
    SET updated_at = inserted_at
    WHERE updated_at IS NULL
    """)

    execute("""
    UPDATE workout_exercises
    SET inserted_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE inserted_at IS NULL OR updated_at IS NULL
    """)

    execute("""
    UPDATE exercise_variations
    SET updated_at = inserted_at
    WHERE updated_at IS NULL
    """)

    alter table(:workout_sections) do
      modify :updated_at, :naive_datetime, null: false
    end

    alter table(:workout_exercises) do
      modify :inserted_at, :naive_datetime, null: false
      modify :updated_at, :naive_datetime, null: false
    end

    alter table(:exercise_variations) do
      modify :updated_at, :naive_datetime, null: false
    end
  end

  def down do
    alter table(:exercise_variations) do
      remove :updated_at
    end

    alter table(:workout_exercises) do
      remove :updated_at
      remove :inserted_at
    end

    alter table(:workout_sections) do
      remove :updated_at
    end
  end
end
