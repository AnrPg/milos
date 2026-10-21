defmodule Palee.Repo.Migrations.AddRoleNotificationTypes do
  use Ecto.Migration

  # ADR-100 coach_client_assigned and ADR-101 coach_note_viewed.
  @before [
    "booking_approved",
    "booking_rejected",
    "booking_pending",
    "booking_timeout",
    "workout_note",
    "workout_changed",
    "workout_deleted",
    "workout_rejected",
    "workout_moved",
    "workout_assigned",
    "workout_assignment_requested",
    "review_submitted",
    "athlete_message",
    "workout_completed",
    "admin_note",
    "challenge_completed",
    "chat_message",
    "invoice_issued",
    "payment_reminder",
    "booking_waitlist_promoted",
    "package_expiring",
    "form_review_submitted",
    "form_review_completed",
    "coaching_reply_overdue",
    "nutrition_plan_updated"
  ]

  @types @before ++
           [
             "appointment_booked",
             "appointment_cancelled",
             "coach_client_assigned",
             "coach_note_viewed"
           ]

  def up, do: replace_notification_types(@types)

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('coach_client_assigned', 'coach_note_viewed')"
    )

    replace_notification_types(@before ++ ["appointment_booked", "appointment_cancelled"])
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
