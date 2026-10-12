defmodule MilosTraining.Repo.Migrations.CreateTrainingLogEntries do
  use Ecto.Migration

  # ADR-118 / TD-033: standalone training-log entries for class or offline
  # workouts that never ran as a timer-backed `workout_executions` row.
  #
  # Tenant-owned (organization_id + user_id) with forced RLS. The policy
  # mirrors the sibling owner-or-tenant tables (workout_executions,
  # injury_reports): the owner can read their own entries across tenants (so
  # personal gamification projections can count them), tenant sessions can
  # read within the organization, and every write must come from the owner
  # inside the owning tenant.
  def up do
    create table(:training_log_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :source_reference_id, :binary_id

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)

      add :booking_id, :binary_id
      add :title, :string, null: false
      add :workout_type, :string
      add :scale_level_slug, :string
      add :performed_at_utc, :utc_datetime_usec, null: false
      add :performed_at_tz, :string, null: false, default: "UTC"
      add :duration_seconds, :integer
      add :perceived_effort, :integer
      add :notes, :text
      add :section_scores, {:array, :map}, null: false, default: []
      add :exercise_modifications, {:array, :map}, null: false, default: []
      add :performed_exercises, {:array, :map}, null: false, default: []
      add :status, :string, null: false, default: "logged"
      add :voided_at, :utc_datetime_usec
      add :void_reason, :text
      add :idempotency_key, :string, null: false
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:training_log_entries, :training_log_entries_source_type_check,
             check: "source_type IN ('class', 'assigned_workout', 'library_workout', 'freeform')"
           )

    create constraint(:training_log_entries, :training_log_entries_status_check,
             check: "status IN ('logged', 'voided')"
           )

    create constraint(:training_log_entries, :training_log_entries_source_reference_check,
             check:
               "(source_type = 'freeform' AND source_reference_id IS NULL) OR " <>
                 "(source_type <> 'freeform' AND source_reference_id IS NOT NULL)"
           )

    create constraint(:training_log_entries, :training_log_entries_perceived_effort_check,
             check: "perceived_effort IS NULL OR (perceived_effort BETWEEN 1 AND 10)"
           )

    create constraint(:training_log_entries, :training_log_entries_duration_check,
             check: "duration_seconds IS NULL OR duration_seconds >= 0"
           )

    create index(:training_log_entries, [:organization_id])
    create index(:training_log_entries, [:user_id, :performed_at_utc])

    create unique_index(:training_log_entries, [:organization_id, :user_id, :idempotency_key],
             name: :training_log_entries_idempotency_index
           )

    # One live log per class / assignment per user. Voiding frees the slot so a
    # corrected entry can be logged; library and freeform entries repeat.
    create unique_index(
             :training_log_entries,
             [:organization_id, :user_id, :source_type, :source_reference_id],
             name: :training_log_entries_live_source_index,
             where: "status = 'logged' AND source_type IN ('class', 'assigned_workout')"
           )

    execute("""
    CREATE POLICY training_log_entries_owner_or_tenant_policy ON training_log_entries
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    WITH CHECK (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      AND organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    )
    """)

    execute("ALTER TABLE training_log_entries ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE training_log_entries FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("ALTER TABLE training_log_entries NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE training_log_entries DISABLE ROW LEVEL SECURITY")

    execute(
      "DROP POLICY IF EXISTS training_log_entries_owner_or_tenant_policy ON training_log_entries"
    )

    drop table(:training_log_entries)
  end
end
