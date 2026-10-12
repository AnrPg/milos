defmodule MilosTraining.Repo.Migrations.CreateOrganizationPurges do
  use Ecto.Migration

  # ADR-107: the reviewed tenant export/purge workflow keeps one platform-level
  # record per purge request. The record must outlive the organization it
  # describes, so `organization_id` deliberately carries no foreign key (a
  # cascade would erase the audit trail together with the tenant) and the
  # vendor ids carry none either. It stores identifiers, counts, policies and
  # object keys only - never tenant PII.

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    create table(:organization_purges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, :binary_id, null: false
      add :organization_slug, :string, null: false
      add :status, :string, null: false, default: "requested"
      add :failed_stage, :string
      add :failure_reason, :string
      add :requested_by_user_id, :binary_id, null: false
      add :requested_at, :utc_datetime_usec, null: false
      add :export_started_at, :utc_datetime_usec
      add :export_completed_at, :utc_datetime_usec
      add :export_key, :string
      add :export_byte_size, :bigint
      add :export_sha256, :string
      add :retained_archive_key, :string
      add :retention_review, {:array, :map}, null: false, default: []
      add :approved_by_user_id, :binary_id
      add :approval_mode, :string
      add :approved_at, :utc_datetime_usec
      add :purge_started_at, :utc_datetime_usec
      add :steps, :map, null: false, default: %{}
      add :completed_at, :utc_datetime_usec
      add :cancelled_by_user_id, :binary_id
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:organization_purges, [:organization_id, :inserted_at])

    # At most one open purge per organization; finished, failed-and-cancelled
    # and completed requests stay as history.
    create unique_index(:organization_purges, [:organization_id],
             where: "status NOT IN ('completed', 'cancelled')",
             name: :organization_purges_one_open_per_organization
           )

    create constraint(:organization_purges, :organization_purges_status_check,
             check:
               "status IN ('requested', 'exporting', 'exported', 'approved', 'purging', 'completed', 'failed', 'cancelled')"
           )

    # Vendor-only, like organization_provisioning_events: no tenant member may
    # read or write purge records. WITH CHECK keeps system sessions workable.
    execute("""
    CREATE POLICY organization_purges_vendor_policy ON organization_purges
    USING (milos_acting_user_is_vendor())
    WITH CHECK (#{@acting_user} IS NULL OR milos_acting_user_is_vendor())
    """)

    execute("ALTER TABLE organization_purges ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_purges FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:organization_purges)
  end
end
