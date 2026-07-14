defmodule MilosTraining.Repo.Migrations.AddWorkoutChangedNotificationType do
  use Ecto.Migration

  def up do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_changed', 'workout_completed', 'admin_note', 'challenge_completed')"
           )
  end

  def down do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_completed', 'admin_note', 'challenge_completed')"
           )
  end
end
