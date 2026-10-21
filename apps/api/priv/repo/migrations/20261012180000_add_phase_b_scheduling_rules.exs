defmodule Palee.Repo.Migrations.AddPhaseBSchedulingRules do
  use Ecto.Migration

  # ADR-097: credit weighting, events, booking windows, cancellation cutoffs,
  # waitlists, guest bookings and their notifications.

  @notification_types [
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
    "package_expiring"
  ]

  @previous_notification_types @notification_types --
                                 ["booking_waitlist_promoted", "package_expiring"]

  def up do
    alter table(:class_types) do
      add :credit_cost, :integer, null: false, default: 1
      add :kind, :string, null: false, default: "class"
    end

    create constraint(:class_types, :class_types_credit_cost,
             check: "credit_cost BETWEEN 1 AND 10"
           )

    create constraint(:class_types, :class_types_kind, check: "kind IN ('class', 'event')")

    alter table(:scheduling_settings) do
      add :default_booking_window_days, :integer
      add :default_cancellation_cutoff_hours, :integer
    end

    alter table(:bookings) do
      add :waitlist_priority, :integer, null: false, default: 0
      add :waitlisted_at, :utc_datetime_usec
      add :guest_name, :string
      add :entitlement_allowance, :string, null: false, default: "class_visits"
    end

    drop constraint(:bookings, :bookings_status_check)

    create constraint(:bookings, :bookings_status_check,
             check: "status IN ('pending', 'approved', 'rejected', 'cancelled', 'waitlisted')"
           )

    create constraint(:bookings, :bookings_entitlement_allowance,
             check: "entitlement_allowance IN ('class_visits', 'event_visits', 'guest_passes')"
           )

    drop_if_exists index(:bookings, [:scheduled_class_id, :user_id],
                     name: :bookings_slot_user_index
                   )

    # Guests are extra bookings of the same member, so only the member's own
    # booking (or waitlist entry) is unique per class.
    create unique_index(:bookings, [:scheduled_class_id, :user_id],
             where: "status IN ('pending', 'approved', 'waitlisted') AND guest_name IS NULL",
             name: :bookings_slot_user_index
           )

    create index(:bookings, [:scheduled_class_id, :waitlist_priority, :waitlisted_at],
             where: "status = 'waitlisted'",
             name: :bookings_waitlist_index
           )

    replace_notification_types(@notification_types)
  end

  def down do
    replace_notification_types(@previous_notification_types)

    drop_if_exists index(:bookings, [:scheduled_class_id, :waitlist_priority, :waitlisted_at],
                     name: :bookings_waitlist_index
                   )

    execute("DELETE FROM bookings WHERE status = 'waitlisted' OR guest_name IS NOT NULL")

    drop_if_exists index(:bookings, [:scheduled_class_id, :user_id],
                     name: :bookings_slot_user_index
                   )

    create unique_index(:bookings, [:scheduled_class_id, :user_id],
             where: "status IN ('pending', 'approved')",
             name: :bookings_slot_user_index
           )

    drop constraint(:bookings, :bookings_entitlement_allowance)
    drop constraint(:bookings, :bookings_status_check)

    create constraint(:bookings, :bookings_status_check,
             check: "status IN ('pending', 'approved', 'rejected', 'cancelled')"
           )

    alter table(:bookings) do
      remove :entitlement_allowance
      remove :guest_name
      remove :waitlisted_at
      remove :waitlist_priority
    end

    alter table(:scheduling_settings) do
      remove :default_cancellation_cutoff_hours
      remove :default_booking_window_days
    end

    drop constraint(:class_types, :class_types_kind)
    drop constraint(:class_types, :class_types_credit_cost)

    alter table(:class_types) do
      remove :kind
      remove :credit_cost
    end
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
