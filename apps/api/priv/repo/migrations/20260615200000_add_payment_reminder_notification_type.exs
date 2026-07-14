defmodule MilosTraining.Repo.Migrations.AddPaymentReminderNotificationType do
  use Ecto.Migration

  @types_with_reminder [
    "booking_approved",
    "booking_rejected",
    "booking_pending",
    "booking_timeout",
    "workout_note",
    "workout_changed",
    "workout_deleted",
    "workout_rejected",
    "workout_moved",
    "athlete_message",
    "workout_completed",
    "admin_note",
    "challenge_completed",
    "chat_message",
    "invoice_issued",
    "payment_reminder"
  ]

  @types_without_reminder @types_with_reminder -- ["payment_reminder"]

  def up do
    replace_type_constraint(@types_with_reminder)
  end

  def down do
    replace_type_constraint(@types_without_reminder)
  end

  defp replace_type_constraint(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{quoted_types(types)})"
           )
  end

  defp quoted_types(types) do
    Enum.map_join(types, ", ", &"'#{&1}'")
  end
end
