defmodule Palee.Repo.Migrations.CreateFacilityLocationsAndCheckIns do
  use Ecto.Migration

  # ADR-097: the Facility context — gym locations, location-scoped classes and
  # open-gym check-ins.

  def up do
    create table(:facility_locations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :address, :text
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:facility_locations, [:id, :organization_id],
             name: :facility_locations_id_organization_index
           )

    create unique_index(:facility_locations, ["organization_id", "lower(name)"],
             where: "archived_at IS NULL",
             name: :facility_locations_organization_name_index
           )

    enable_tenant_rls("facility_locations")

    alter table(:scheduled_classes) do
      add :location_id, :binary_id
    end

    alter table(:class_series) do
      add :location_id, :binary_id
    end

    # Locations are archived, never deleted, so the references restrict deletes.
    for table <- ["scheduled_classes", "class_series"] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_location_id_fkey
      FOREIGN KEY (location_id, organization_id)
      REFERENCES facility_locations (id, organization_id)
      """)

      create index(table, [:location_id], where: "location_id IS NOT NULL")
    end

    create table(:facility_check_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :location_id, :binary_id
      add :checked_in_on, :date, null: false
      add :checked_in_at, :utc_datetime_usec, null: false
      add :source, :string, null: false
      add :recorded_by_id, :binary_id
      add :reservation_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE facility_check_ins
    ADD CONSTRAINT facility_check_ins_location_id_fkey
    FOREIGN KEY (location_id, organization_id)
    REFERENCES facility_locations (id, organization_id)
    """)

    create constraint(:facility_check_ins, :facility_check_ins_source,
             check: "source IN ('self', 'staff')"
           )

    # One open-gym visit per member and day.
    create unique_index(:facility_check_ins, [:organization_id, :user_id, :checked_in_on],
             name: :facility_check_ins_daily_index
           )

    create index(:facility_check_ins, [:organization_id, :checked_in_on])

    enable_tenant_rls("facility_check_ins")
  end

  def down do
    drop table(:facility_check_ins)

    for table <- ["class_series", "scheduled_classes"] do
      execute("ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_location_id_fkey")

      alter table(table) do
        remove :location_id
      end
    end

    drop table(:facility_locations)
  end

  defp enable_tenant_rls(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
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
