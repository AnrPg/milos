defmodule Palee.Repo.Migrations.ClassSpacesCleaningSchedulesAndPlacements do
  @moduledoc """
  ADR-202: classes and series take an optional space; each space may have a
  cleaning schedule (weekdays, times and a comment); machines record how many
  of them stand in which space; floor plans are `floor_plan` tenant media.

  Every reference to a space is a composite key, so it cannot leave the gym,
  and losing a space clears only the class's space, never its gym.
  """

  use Ecto.Migration

  @new_tables ~w(housekeeping_schedules inventory_machine_placements)

  def up do
    for table <- ~w(scheduled_classes class_series) do
      alter table(table) do
        add :space_id, :binary_id
      end

      execute("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{table}_space_fkey
        FOREIGN KEY (space_id, organization_id)
        REFERENCES spaces (id, organization_id)
        ON DELETE SET NULL (space_id)
      """)
    end

    create index(:scheduled_classes, [:space_id, :scheduled_at], where: "space_id IS NOT NULL")

    create table(:housekeeping_schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :space_id, :binary_id, null: false
      add :weekdays, {:array, :integer}, null: false, default: []
      add :times, {:array, :time}, null: false, default: []
      add :comment, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:housekeeping_schedules, [:space_id])
    create index(:housekeeping_schedules, [:organization_id])

    execute("""
    ALTER TABLE housekeeping_schedules
      ADD CONSTRAINT housekeeping_schedules_space_fkey
      FOREIGN KEY (space_id, organization_id)
      REFERENCES spaces (id, organization_id) ON DELETE CASCADE
    """)

    create table(:inventory_machine_placements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :machine_id, :binary_id, null: false
      add :space_id, :binary_id, null: false
      add :quantity, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:inventory_machine_placements, :inventory_machine_placements_quantity_check,
             check: "quantity > 0"
           )

    create unique_index(:inventory_machine_placements, [:machine_id, :space_id])
    create index(:inventory_machine_placements, [:space_id])

    execute("""
    ALTER TABLE inventory_machine_placements
      ADD CONSTRAINT inventory_machine_placements_machine_fkey
      FOREIGN KEY (machine_id, organization_id)
      REFERENCES inventory_machines (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE inventory_machine_placements
      ADD CONSTRAINT inventory_machine_placements_space_fkey
      FOREIGN KEY (space_id, organization_id)
      REFERENCES spaces (id, organization_id) ON DELETE CASCADE
    """)

    Enum.each(@new_tables, &tenant_security/1)

    media_purposes(~w(box_photo shop_product_photo floor_plan))
  end

  def down do
    execute("DELETE FROM media_tenant_objects WHERE purpose = 'floor_plan'")
    media_purposes(~w(box_photo shop_product_photo))
    drop table(:inventory_machine_placements)
    drop table(:housekeeping_schedules)

    for table <- ~w(scheduled_classes class_series) do
      alter table(table) do
        remove :space_id
      end
    end
  end

  defp media_purposes(list) do
    execute("ALTER TABLE media_tenant_objects DROP CONSTRAINT media_tenant_objects_purpose_check")

    create constraint(:media_tenant_objects, :media_tenant_objects_purpose_check,
             check: "purpose IN (#{Enum.map_join(list, ", ", &"'#{&1}'")})"
           )
  end

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
