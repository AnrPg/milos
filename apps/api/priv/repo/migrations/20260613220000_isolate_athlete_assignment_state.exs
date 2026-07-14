defmodule MilosTraining.Repo.Migrations.IsolateAthleteAssignmentState do
  use Ecto.Migration

  def up do
    alter table(:assigned_workout_athletes) do
      add :scheduled_for, :date
    end

    execute """
    UPDATE assigned_workout_athletes AS links
    SET scheduled_for = assignments.scheduled_for
    FROM assigned_workouts AS assignments
    WHERE assignments.id = links.assigned_workout_id
    """

    alter table(:assigned_workout_athletes) do
      modify :scheduled_for, :date, null: false
    end

    create index(:assigned_workout_athletes, [:athlete_id, :scheduled_for])

    alter table(:assignment_messages) do
      add :athlete_id, :binary_id
    end

    execute """
    UPDATE assignment_messages AS messages
    SET athlete_id = messages.sender_id
    WHERE EXISTS (
      SELECT 1
      FROM assigned_workout_athletes AS links
      WHERE links.assigned_workout_id = messages.assigned_workout_id
        AND links.athlete_id = messages.sender_id
    )
    """

    execute """
    UPDATE assignment_messages AS messages
    SET athlete_id = recipients.athlete_id
    FROM (
      SELECT assigned_workout_id, MIN(athlete_id::text)::uuid AS athlete_id
      FROM assigned_workout_athletes
      GROUP BY assigned_workout_id
      HAVING COUNT(*) = 1
    ) AS recipients
    WHERE recipients.assigned_workout_id = messages.assigned_workout_id
      AND messages.athlete_id IS NULL
    """

    create index(:assignment_messages, [:assigned_workout_id, :athlete_id, :inserted_at])
  end

  def down do
    drop index(:assignment_messages, [:assigned_workout_id, :athlete_id, :inserted_at])

    alter table(:assignment_messages) do
      remove :athlete_id
    end

    drop index(:assigned_workout_athletes, [:athlete_id, :scheduled_for])

    alter table(:assigned_workout_athletes) do
      remove :scheduled_for
    end
  end
end
