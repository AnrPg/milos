defmodule MilosTraining.Repo.Migrations.AddWorkoutCompletedNotificationType do
  use Ecto.Migration

  def up do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_completed', 'admin_note')"
           )
  end

  def down do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'admin_note')"
           )
  end
end
