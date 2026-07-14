defmodule MilosTraining.Repo.Migrations.EnforceUniqueAssignmentHeaders do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM assigned_workout_athletes AS duplicate_link
    USING assigned_workout_athletes AS keeper_link,
    (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for
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
          PARTITION BY master_workout_id, scheduled_for
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id
      FROM assigned_workouts
    ) AS ranked
    WHERE athlete_link.assigned_workout_id = ranked.id
      AND ranked.id <> ranked.keeper_id
    """)

    execute("""
    WITH ranked AS (
      SELECT
        id,
        admin_notes,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id,
        row_number() OVER (
          PARTITION BY master_workout_id, scheduled_for
          ORDER BY
            CASE WHEN admin_notes IS NULL OR admin_notes = '' THEN 1 ELSE 0 END,
            inserted_at DESC,
            id DESC
        ) AS note_rank
      FROM assigned_workouts
    ),
    best_notes AS (
      SELECT keeper_id, admin_notes
      FROM ranked
      WHERE note_rank = 1
        AND admin_notes IS NOT NULL
        AND admin_notes <> ''
    )
    UPDATE assigned_workouts AS keeper
    SET admin_notes = best_notes.admin_notes
    FROM best_notes
    WHERE keeper.id = best_notes.keeper_id
      AND (keeper.admin_notes IS NULL OR keeper.admin_notes = '')
    """)

    execute("""
    DELETE FROM assigned_workouts AS assignment
    USING (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY master_workout_id, scheduled_for
          ORDER BY inserted_at ASC, id ASC
        ) AS keeper_id
      FROM assigned_workouts
    ) AS ranked
    WHERE assignment.id = ranked.id
      AND ranked.id <> ranked.keeper_id
    """)

    create unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for],
             name: :assigned_workouts_master_workout_id_scheduled_for_index
           )
  end

  def down do
    drop_if_exists(
      unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for],
        name: :assigned_workouts_master_workout_id_scheduled_for_index
      )
    )
  end
end
