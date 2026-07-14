defmodule MilosTraining.Repo.Migrations.NormalizeAssignedWorkoutNotes do
  use Ecto.Migration

  def up do
    drop_if_exists(
      unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :admin_notes],
        name: :assigned_workouts_workout_date_notes_index
      )
    )

    execute("""
    UPDATE assigned_workouts
    SET admin_notes = NULLIF(BTRIM(admin_notes), '')
    WHERE admin_notes IS NOT NULL
    """)

    execute("""
    DELETE FROM assigned_workout_athletes AS duplicate_link
    USING assigned_workout_athletes AS keeper_link,
    (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for, admin_notes
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id
      FROM assigned_workouts
    ) AS ranked
    WHERE duplicate_link.assigned_workout_id = ranked.id
      AND ranked.id <> ranked.keeper_id
      AND keeper_link.assigned_workout_id = ranked.keeper_id
      AND keeper_link.athlete_id = duplicate_link.athlete_id
    """)

    execute("""
    UPDATE assigned_workout_athletes AS athlete_link
    SET assigned_workout_id = ranked.keeper_id
    FROM (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for, admin_notes
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id
      FROM assigned_workouts
    ) AS ranked
    WHERE athlete_link.assigned_workout_id = ranked.id
      AND ranked.id <> ranked.keeper_id
    """)

    execute("""
    DELETE FROM assigned_workouts AS assignment
    USING (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for, admin_notes
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id
      FROM assigned_workouts
    ) AS ranked
    WHERE assignment.id = ranked.id
      AND ranked.id <> ranked.keeper_id
    """)

    create unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :admin_notes],
             name: :assigned_workouts_workout_date_notes_index,
             nulls_distinct: false
           )
  end

  def down do
    drop_if_exists(
      unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :admin_notes],
        name: :assigned_workouts_workout_date_notes_index
      )
    )

    create unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :admin_notes],
             name: :assigned_workouts_workout_date_notes_index,
             nulls_distinct: false
           )
  end
end
