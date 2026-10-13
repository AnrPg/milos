defmodule MilosTraining.Repo.Migrations.CreateAppointments do
  use Ecto.Migration

  # ADR-098: coach-published appointment slots (PT sessions, assessments) and
  # the clients booked into them.

  @phase_c_types [
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

  @types @phase_c_types ++ ["appointment_booked", "appointment_cancelled"]

  def up do
    create table(:appointment_slots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :coach_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :format, :string, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :duration_minutes, :integer, null: false
      add :capacity, :integer, null: false, default: 1
      add :location_id, :binary_id
      add :notes, :text
      add :cancelled_at, :utc_datetime_usec
      add :created_by_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:appointment_slots, [:id, :organization_id],
             name: :appointment_slots_id_organization_index
           )

    create index(:appointment_slots, [:organization_id, :starts_at])
    create index(:appointment_slots, [:coach_id, :starts_at])

    create constraint(:appointment_slots, :appointment_slots_kind,
             check: "kind IN ('pt_session', 'assessment')"
           )

    create constraint(:appointment_slots, :appointment_slots_format,
             check:
               "(format = 'one_to_one' AND capacity = 1) OR (format = 'semi_private' AND capacity BETWEEN 2 AND 4)"
           )

    create constraint(:appointment_slots, :appointment_slots_duration,
             check: "duration_minutes BETWEEN 15 AND 240"
           )

    execute("""
    ALTER TABLE appointment_slots
    ADD CONSTRAINT appointment_slots_location_id_fkey
    FOREIGN KEY (location_id, organization_id)
    REFERENCES facility_locations (id, organization_id)
    """)

    enable_tenant_rls("appointment_slots")

    create table(:appointment_bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slot_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "booked"
      add :allowance, :string, null: false
      add :reservation_id, :binary_id
      add :booked_by_id, :binary_id
      add :late_cancellation, :boolean, null: false, default: false
      add :cancelled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE appointment_bookings
    ADD CONSTRAINT appointment_bookings_slot_id_fkey
    FOREIGN KEY (slot_id, organization_id)
    REFERENCES appointment_slots (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:appointment_bookings, :appointment_bookings_status,
             check: "status IN ('booked', 'cancelled', 'attended', 'no_show')"
           )

    create constraint(:appointment_bookings, :appointment_bookings_allowance,
             check: "allowance IN ('pt_sessions', 'assessments')"
           )

    create unique_index(:appointment_bookings, [:slot_id, :user_id],
             where: "status <> 'cancelled'",
             name: :appointment_bookings_slot_user_index
           )

    create index(:appointment_bookings, [:user_id, :inserted_at])
    enable_tenant_rls("appointment_bookings")

    replace_notification_types(@types)
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('appointment_booked', 'appointment_cancelled')"
    )

    replace_notification_types(@phase_c_types)
    drop table(:appointment_bookings)
    drop table(:appointment_slots)
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end

  defp enable_tenant_rls(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
