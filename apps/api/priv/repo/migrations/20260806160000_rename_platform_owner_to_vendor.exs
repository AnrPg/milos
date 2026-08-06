defmodule MilosTraining.Repo.Migrations.RenamePlatformOwnerToVendor do
  use Ecto.Migration

  # ADR-089: "platform owner" collided with the tenant-scoped `owner` role
  # (organization_memberships.role). Renamed to "vendor" — see ADR-089.

  def up do
    rename table(:platform_owners), to: table(:vendors)
    rename table(:organization_provisioning_events), :platform_owner_user_id, to: :vendor_user_id

    rename_if_exists("platform_owners_user_id_index", "vendors_user_id_index", :index)
    rename_if_exists("platform_owners_status_check", "vendors_status_check", :constraint, "vendors")
    rename_if_exists("platform_owners_user_id_fkey", "vendors_user_id_fkey", :constraint, "vendors")
    rename_if_exists("platform_owners_pkey", "vendors_pkey", :constraint, "vendors")

    rename_if_exists(
      "organization_provisioning_events_platform_owner_user_id_fkey",
      "organization_provisioning_events_vendor_user_id_fkey",
      :constraint,
      "organization_provisioning_events"
    )
  end

  def down do
    rename_if_exists(
      "organization_provisioning_events_vendor_user_id_fkey",
      "organization_provisioning_events_platform_owner_user_id_fkey",
      :constraint,
      "organization_provisioning_events"
    )

    rename_if_exists("vendors_pkey", "platform_owners_pkey", :constraint, "vendors")
    rename_if_exists("vendors_user_id_fkey", "platform_owners_user_id_fkey", :constraint, "vendors")
    rename_if_exists("vendors_status_check", "platform_owners_status_check", :constraint, "vendors")
    rename_if_exists("vendors_user_id_index", "platform_owners_user_id_index", :index)

    rename table(:organization_provisioning_events), :vendor_user_id, to: :platform_owner_user_id
    rename table(:vendors), to: table(:platform_owners)
  end

  defp rename_if_exists(from_name, to_name, :index) do
    execute("ALTER INDEX IF EXISTS #{from_name} RENAME TO #{to_name}")
  end

  defp rename_if_exists(from_name, to_name, :constraint, table_name) do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '#{from_name}'
      ) THEN
        ALTER TABLE #{table_name} RENAME CONSTRAINT #{from_name} TO #{to_name};
      END IF;
    END
    $$;
    """)
  end
end
