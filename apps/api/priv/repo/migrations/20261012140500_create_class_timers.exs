defmodule Palee.Repo.Migrations.CreateClassTimers do
  use Ecto.Migration

  # A coach-run timer for one scheduled class, shown on the gym's wall display
  # and followed on members' phones. One row per class.
  def up do
    create table(:class_timers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "ready"
      add :current_segment_index, :integer, null: false, default: 0
      add :segment_started_at_utc, :utc_datetime_usec
      add :paused_elapsed_ms, :integer, null: false, default: 0
      add :duration_adjustments, :map, null: false, default: %{}
      # Timer for classes without a structured workout (free text or none).
      add :timer_preset, :map
      add :controlled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:class_timers, [:scheduled_class_id])
    create index(:class_timers, [:organization_id])

    predicate = """
    palee_acting_user_is_vendor()
    OR class_timers.organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
    """

    execute("""
    CREATE POLICY class_timers_tenant_policy ON class_timers
    USING (#{predicate})
    WITH CHECK (#{predicate})
    """)

    execute("ALTER TABLE class_timers ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE class_timers FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:class_timers)
  end
end
