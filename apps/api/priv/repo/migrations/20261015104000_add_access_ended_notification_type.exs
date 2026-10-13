defmodule MilosTraining.Repo.Migrations.AddAccessEndedNotificationType do
  use Ecto.Migration

  @types ~w(
    booking_approved
    booking_rejected
    booking_pending
    booking_timeout
    workout_note
    workout_changed
    workout_deleted
    workout_rejected
    workout_moved
    workout_assigned
    workout_assignment_requested
    review_submitted
    athlete_message
    workout_completed
    admin_note
    challenge_completed
    chat_message
    invoice_issued
    payment_reminder
    booking_waitlist_promoted
    package_expiring
    form_review_submitted
    form_review_completed
    coaching_reply_overdue
    nutrition_plan_updated
    appointment_booked
    appointment_cancelled
    coach_client_assigned
    coach_note_viewed
    inventory_repair_needed
    inventory_stock_low
    inventory_digest
    subscription_expiring
    subscription_grace
    access_ended
  )

  @previous_types @types -- ["access_ended"]

  def up, do: replace_type_constraint(@types)
  def down, do: replace_type_constraint(@previous_types)

  defp replace_type_constraint(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
