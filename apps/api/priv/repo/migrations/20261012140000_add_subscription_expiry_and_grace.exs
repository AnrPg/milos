defmodule MilosTraining.Repo.Migrations.AddSubscriptionExpiryAndGrace do
  use Ecto.Migration

  @types [
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
    "subscription_expiring",
    "subscription_grace"
  ]

  @previous_types @types -- ["subscription_expiring", "subscription_grace"]

  def up do
    alter table(:finance_settings) do
      add :subscription_expiry_reminder_days, :integer, null: false, default: 5
      add :subscription_grace_days, :integer, null: false, default: 3
    end

    alter table(:membership_package_subscriptions) do
      add :expiry_reminder_sent_at, :utc_datetime_usec
      add :grace_notice_sent_at, :utc_datetime_usec
    end

    replace_type_constraint(@types)
  end

  def down do
    replace_type_constraint(@previous_types)

    alter table(:membership_package_subscriptions) do
      remove :expiry_reminder_sent_at
      remove :grace_notice_sent_at
    end

    alter table(:finance_settings) do
      remove :subscription_expiry_reminder_days
      remove :subscription_grace_days
    end
  end

  defp replace_type_constraint(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
