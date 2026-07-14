defmodule MilosTraining.Repo.Migrations.Phase2AthleteStatusAndNotificationTypes do
  use Ecto.Migration

  def up do
    # Expand notification types: workout_deleted, workout_rejected, athlete_message
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_changed', 'workout_deleted', 'workout_rejected', 'athlete_message', 'workout_completed', 'admin_note', 'challenge_completed')"
           )

    # Athlete rejection status on the assignment-athlete join row
    alter table(:assigned_workout_athletes) do
      add :athlete_status, :string, null: true
    end

    create constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check,
             check: "athlete_status IS NULL OR athlete_status IN ('accepted', 'rejected')"
           )
  end

  def down do
    drop constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check)

    alter table(:assigned_workout_athletes) do
      remove :athlete_status
    end

    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_changed', 'workout_completed', 'admin_note', 'challenge_completed')"
           )
  end
end
