defmodule Palee.Repo.Migrations.DayWorkouts do
  @moduledoc """
  ADR-230: a WOD for a whole day. `day_workouts` holds one rule per gym day,
  optionally narrowed to a class type and/or a branch; NULL means «all».
  `scheduled_classes.day_workout_id` records which rule gave a class its WOD:
  set = inherited, NULL with a WOD = the class's own WOD (an override).

  `local_date` is the gym's own date (ADR-176). Rules point at the copy filed
  in that day's Classes folder, never at the library template.
  """

  use Ecto.Migration

  def up do
    create table(:day_workouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :local_date, :date, null: false
      add :class_type_id, :binary_id
      add :location_id, :binary_id

      # Losing the filed copy drops the rule; its classes keep their WOD
      # through the restrict on scheduled_classes.master_workout_id.
      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :set_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    # One rule per day and scope; «all types» / «all branches» are scopes too.
    execute("""
    CREATE UNIQUE INDEX day_workouts_scope_index
      ON day_workouts (organization_id, local_date, class_type_id, location_id)
      NULLS NOT DISTINCT
    """)

    create unique_index(:day_workouts, [:id, :organization_id],
             name: :day_workouts_id_organization_index
           )

    create index(:day_workouts, [:master_workout_id])

    execute("""
    ALTER TABLE day_workouts
      ADD CONSTRAINT day_workouts_class_type_fkey
      FOREIGN KEY (class_type_id, organization_id)
      REFERENCES class_types (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE day_workouts
      ADD CONSTRAINT day_workouts_location_fkey
      FOREIGN KEY (location_id, organization_id)
      REFERENCES facility_locations (id, organization_id) ON DELETE CASCADE
    """)

    alter table(:scheduled_classes) do
      add :day_workout_id, :binary_id
    end

    execute("""
    ALTER TABLE scheduled_classes
      ADD CONSTRAINT scheduled_classes_day_workout_fkey
      FOREIGN KEY (day_workout_id, organization_id)
      REFERENCES day_workouts (id, organization_id)
      ON DELETE SET NULL (day_workout_id)
    """)

    create index(:scheduled_classes, [:day_workout_id], where: "day_workout_id IS NOT NULL")

    execute("""
    CREATE TRIGGER day_workouts_apply_tenant_context
    BEFORE INSERT OR UPDATE ON day_workouts
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY day_workouts_tenant_policy ON day_workouts
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE day_workouts ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE day_workouts FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute(
      "ALTER TABLE scheduled_classes DROP CONSTRAINT IF EXISTS scheduled_classes_day_workout_fkey"
    )

    alter table(:scheduled_classes) do
      remove :day_workout_id
    end

    drop table(:day_workouts)
  end
end
