defmodule Palee.Repo.Migrations.SpacePhotosCleaningPointsAndMachinePhotos do
  @moduledoc """
  ADR-290: what the floor plans of ADR-202 grow into.

    * `space_settings`: one row per gym; `floor_plans_in_classes` lets the
      people who see a class open the floor plan with its room coloured.
      Each floor can stay hidden (`space_floor_plans.shown_in_classes`).
    * `space_photos`: photos of a room, to get an idea of it. Each one is
      shown on the public box page only when its uploader says so.
    * `space_cleaning_points`: the visual cleaning checklist of a room, a
      photo and what to clean there. A finished cleaning keeps what the
      janitor answered for each point (`housekeeping_entries.point_results`).
    * `inventory_machine_events.media_ids`: up to 10 photos on a log line.
    * `inventory_machine_placements.positions`: where on the floor plan each
      item stands (at most one pin per item placed in that space).

  Photos are private tenant media read through signed URLs.
  """

  use Ecto.Migration

  @new_tables ~w(space_settings space_photos space_cleaning_points)
  @new_purposes ~w(space_photo cleaning_photo machine_photo)
  @notification_types ~w(cleaning_point_not_cleaned)

  def up do
    create table(:space_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :floor_plans_in_classes, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:space_settings, [:organization_id])

    alter table(:space_floor_plans) do
      add :shown_in_classes, :boolean, null: false, default: true
    end

    create table(:space_photos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :space_id, :binary_id, null: false
      add :media_id, :binary_id, null: false
      add :caption, :text
      add :public, :boolean, null: false, default: false
      add :sort_order, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:space_photos, [:space_id, :sort_order])
    create unique_index(:space_photos, [:media_id])
    create index(:space_photos, [:organization_id], where: "public")

    create table(:space_cleaning_points, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :space_id, :binary_id, null: false
      add :media_id, :binary_id, null: false
      add :instruction, :text, null: false
      add :sort_order, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:space_cleaning_points, [:space_id, :sort_order])
    create unique_index(:space_cleaning_points, [:media_id])

    for table <- ~w(space_photos space_cleaning_points) do
      execute("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{table}_space_fkey
        FOREIGN KEY (space_id, organization_id)
        REFERENCES spaces (id, organization_id) ON DELETE CASCADE
      """)
    end

    alter table(:housekeeping_entries) do
      add :point_results, :map, null: false, default: fragment("'[]'::jsonb")
    end

    alter table(:inventory_machine_events) do
      add :media_ids, {:array, :binary_id}, null: false, default: []
    end

    create constraint(:inventory_machine_events, :inventory_machine_events_media_ids_check,
             check: "cardinality(media_ids) <= 10"
           )

    alter table(:inventory_machine_placements) do
      add :positions, :map, null: false, default: fragment("'[]'::jsonb")
    end

    create constraint(
             :inventory_machine_placements,
             :inventory_machine_placements_positions_check,
             check:
               "jsonb_typeof(positions) = 'array' AND jsonb_array_length(positions) <= quantity"
           )

    Enum.each(@new_tables, &tenant_security/1)

    rewrite_check("media_tenant_objects", "purpose", &Enum.uniq(&1 ++ @new_purposes))
    rewrite_check("notifications", "type", &Enum.uniq(&1 ++ @notification_types))
  end

  def down do
    execute("DELETE FROM media_tenant_objects WHERE purpose IN (#{quoted(@new_purposes)})")
    execute("DELETE FROM notifications WHERE type IN (#{quoted(@notification_types)})")

    rewrite_check("media_tenant_objects", "purpose", &(&1 -- @new_purposes))
    rewrite_check("notifications", "type", &(&1 -- @notification_types))

    drop constraint(:inventory_machine_placements, :inventory_machine_placements_positions_check)

    alter table(:inventory_machine_placements) do
      remove :positions
    end

    drop constraint(:inventory_machine_events, :inventory_machine_events_media_ids_check)

    alter table(:inventory_machine_events) do
      remove :media_ids
    end

    alter table(:housekeeping_entries) do
      remove :point_results
    end

    drop table(:space_cleaning_points)
    drop table(:space_photos)

    alter table(:space_floor_plans) do
      remove :shown_in_classes
    end

    drop table(:space_settings)
  end

  # Other branches add purposes and notification types too: the new list is
  # the constraint as it stands now, changed.
  defp rewrite_check(table, column, change) do
    flush()
    name = "#{table}_#{column}_check"

    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1 AND conrelid = to_regclass($2::text)",
        [name, table]
      )

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{column} IN (#{quoted(change.(current))}))"
    )
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")

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
