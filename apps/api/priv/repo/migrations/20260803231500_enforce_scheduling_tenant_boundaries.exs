defmodule MilosTraining.Repo.Migrations.EnforceSchedulingTenantBoundaries do
  use Ecto.Migration

  def up do
    drop_if_exists index(:class_types, [:slug])

    create unique_index(:class_types, [:organization_id, :slug],
             name: :class_types_organization_slug_index
           )

    drop_if_exists index(:scheduling_settings, [:organization_id])

    create unique_index(:scheduling_settings, [:organization_id],
             name: :scheduling_settings_organization_unique_index
           )

    for table <- [
          :class_types,
          :class_series,
          :scheduled_classes,
          :bookings,
          :class_attendance_records
        ] do
      create unique_index(table, [:id, :organization_id], name: "#{table}_id_organization_index")
    end

    execute("""
    ALTER TABLE class_series
    ADD CONSTRAINT class_series_class_type_same_organization_fkey
    FOREIGN KEY (class_type_id, organization_id)
    REFERENCES class_types (id, organization_id)
    """)

    execute("""
    ALTER TABLE scheduled_classes
    ADD CONSTRAINT scheduled_classes_class_type_same_organization_fkey
    FOREIGN KEY (class_type_id, organization_id)
    REFERENCES class_types (id, organization_id)
    """)

    execute("""
    ALTER TABLE scheduled_classes
    ADD CONSTRAINT scheduled_classes_series_same_organization_fkey
    FOREIGN KEY (class_series_id, organization_id)
    REFERENCES class_series (id, organization_id)
    """)

    execute("""
    ALTER TABLE bookings
    ADD CONSTRAINT bookings_scheduled_class_same_organization_fkey
    FOREIGN KEY (scheduled_class_id, organization_id)
    REFERENCES scheduled_classes (id, organization_id)
    """)

    execute("""
    ALTER TABLE class_attendance_records
    ADD CONSTRAINT attendance_scheduled_class_same_organization_fkey
    FOREIGN KEY (scheduled_class_id, organization_id)
    REFERENCES scheduled_classes (id, organization_id)
    """)

    execute("""
    ALTER TABLE class_attendance_records
    ADD CONSTRAINT attendance_booking_same_organization_fkey
    FOREIGN KEY (booking_id, organization_id)
    REFERENCES bookings (id, organization_id)
    """)
  end

  def down do
    execute(
      "ALTER TABLE class_attendance_records DROP CONSTRAINT IF EXISTS attendance_booking_same_organization_fkey"
    )

    execute(
      "ALTER TABLE class_attendance_records DROP CONSTRAINT IF EXISTS attendance_scheduled_class_same_organization_fkey"
    )

    execute(
      "ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_scheduled_class_same_organization_fkey"
    )

    execute(
      "ALTER TABLE scheduled_classes DROP CONSTRAINT IF EXISTS scheduled_classes_series_same_organization_fkey"
    )

    execute(
      "ALTER TABLE scheduled_classes DROP CONSTRAINT IF EXISTS scheduled_classes_class_type_same_organization_fkey"
    )

    execute(
      "ALTER TABLE class_series DROP CONSTRAINT IF EXISTS class_series_class_type_same_organization_fkey"
    )

    for table <- [
          :class_types,
          :class_series,
          :scheduled_classes,
          :bookings,
          :class_attendance_records
        ] do
      drop_if_exists index(table, [:id, :organization_id], name: "#{table}_id_organization_index")
    end

    drop_if_exists index(:scheduling_settings, [:organization_id],
                     name: :scheduling_settings_organization_unique_index
                   )

    create index(:scheduling_settings, [:organization_id])

    drop_if_exists index(:class_types, [:organization_id, :slug],
                     name: :class_types_organization_slug_index
                   )

    create unique_index(:class_types, [:slug])
  end
end
