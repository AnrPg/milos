defmodule Palee.Repo.Migrations.SpacesFromHousekeepingAreas do
  @moduledoc """
  ADR-202: the cleaning areas of ADR-102 become the gym's spaces (rooms and
  areas of a branch). The table is renamed in place, so every area keeps its
  id, name, branch and tasks and every cleaning entry keeps pointing at it;
  nothing is copied. Spaces gain a description, directions and an optional
  area drawn on one of the branch's floor plans. Floor plans and
  unavailability windows are new tenant tables with the usual RLS.
  """

  use Ecto.Migration

  @new_tables ~w(space_floor_plans space_unavailabilities)

  def up do
    execute("ALTER TABLE housekeeping_areas RENAME TO spaces")
    execute("ALTER INDEX housekeeping_areas_pkey RENAME TO spaces_pkey")

    execute(
      "ALTER INDEX housekeeping_areas_id_organization_index RENAME TO spaces_id_organization_index"
    )

    execute(
      "ALTER INDEX housekeeping_areas_organization_id_index RENAME TO spaces_organization_id_index"
    )

    execute(
      "ALTER TABLE spaces RENAME CONSTRAINT housekeeping_areas_organization_id_fkey TO spaces_organization_id_fkey"
    )

    execute(
      "ALTER TRIGGER housekeeping_areas_apply_tenant_context ON spaces RENAME TO spaces_apply_tenant_context"
    )

    execute(
      "ALTER POLICY housekeeping_areas_tenant_policy ON spaces RENAME TO spaces_tenant_policy"
    )

    alter table(:spaces) do
      add :description, :text
      add :directions, :text
      add :floor_plan_id, :binary_id
      # A normalized (0..1) polygon on the floor plan: %{"points" => [[x, y], ...]}.
      add :area, :map
    end

    create index(:spaces, [:organization_id, :location_id])

    create table(:space_floor_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :location_id, :binary_id
      add :name, :string, null: false
      add :media_id, :binary_id, null: false
      add :sort_order, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:space_floor_plans, [:id, :organization_id],
             name: :space_floor_plans_id_organization_index
           )

    create index(:space_floor_plans, [:organization_id, :location_id])

    execute("""
    ALTER TABLE spaces
      ADD CONSTRAINT spaces_floor_plan_fkey
      FOREIGN KEY (floor_plan_id, organization_id)
      REFERENCES space_floor_plans (id, organization_id)
      ON DELETE SET NULL (floor_plan_id)
    """)

    create table(:space_unavailabilities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :space_id, :binary_id, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :reason, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:space_unavailabilities, :space_unavailabilities_order_check,
             check: "ends_at > starts_at"
           )

    execute("""
    ALTER TABLE space_unavailabilities
      ADD CONSTRAINT space_unavailabilities_space_fkey
      FOREIGN KEY (space_id, organization_id)
      REFERENCES spaces (id, organization_id) ON DELETE CASCADE
    """)

    create index(:space_unavailabilities, [:space_id, :ends_at])

    Enum.each(@new_tables, &tenant_security/1)
  end

  def down do
    drop table(:space_unavailabilities)
    execute("ALTER TABLE spaces DROP CONSTRAINT spaces_floor_plan_fkey")
    drop table(:space_floor_plans)
    drop index(:spaces, [:organization_id, :location_id])

    alter table(:spaces) do
      remove :description
      remove :directions
      remove :floor_plan_id
      remove :area
    end

    execute(
      "ALTER POLICY spaces_tenant_policy ON spaces RENAME TO housekeeping_areas_tenant_policy"
    )

    execute(
      "ALTER TRIGGER spaces_apply_tenant_context ON spaces RENAME TO housekeeping_areas_apply_tenant_context"
    )

    execute(
      "ALTER TABLE spaces RENAME CONSTRAINT spaces_organization_id_fkey TO housekeeping_areas_organization_id_fkey"
    )

    execute(
      "ALTER INDEX spaces_organization_id_index RENAME TO housekeeping_areas_organization_id_index"
    )

    execute(
      "ALTER INDEX spaces_id_organization_index RENAME TO housekeeping_areas_id_organization_index"
    )

    execute("ALTER INDEX spaces_pkey RENAME TO housekeeping_areas_pkey")
    execute("ALTER TABLE spaces RENAME TO housekeeping_areas")
  end

  # The same tenant boundary as every tenant table (ADR-102's migration).
  defp tenant_security(table) do
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
