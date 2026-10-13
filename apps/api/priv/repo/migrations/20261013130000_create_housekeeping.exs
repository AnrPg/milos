defmodule MilosTraining.Repo.Migrations.CreateHousekeeping do
  use Ecto.Migration

  # ADR-102: cleaning areas with a task checklist, and cleaning entries.
  def change do
    create table(:housekeeping_areas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :location_id, :binary_id
      add :tasks, {:array, :string}, null: false, default: []
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:housekeeping_areas, [:id, :organization_id],
             name: :housekeeping_areas_id_organization_index
           )

    create index(:housekeeping_areas, [:organization_id])

    create table(:housekeeping_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :area_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :tasks_done, {:array, :string}, null: false, default: []
      add :note, :text
      timestamps(type: :utc_datetime_usec)
    end

    execute(
      """
      ALTER TABLE housekeeping_entries
      ADD CONSTRAINT housekeeping_entries_area_fkey
      FOREIGN KEY (area_id, organization_id)
      REFERENCES housekeeping_areas (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE housekeeping_entries DROP CONSTRAINT housekeeping_entries_area_fkey"
    )

    create index(:housekeeping_entries, [:organization_id, :started_at])
    create index(:housekeeping_entries, [:area_id, :started_at])

    for table <- ["housekeeping_areas", "housekeeping_entries"] do
      execute(
        """
        CREATE TRIGGER #{table}_apply_tenant_context
        BEFORE INSERT OR UPDATE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
        """,
        "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
      )

      execute(
        """
        CREATE POLICY #{table}_tenant_policy ON #{table}
        USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        """,
        "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
      )

      execute(
        "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
      )

      execute(
        "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      )
    end
  end
end
