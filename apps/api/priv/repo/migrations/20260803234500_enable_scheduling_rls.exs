defmodule MilosTraining.Repo.Migrations.EnableSchedulingRls do
  use Ecto.Migration

  @tables ~w(
    class_types
    scheduling_settings
    class_series
    scheduled_classes
    bookings
    class_attendance_records
  )

  def up do
    Enum.each(@tables, fn table ->
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end)
  end

  def down do
    Enum.each(@tables, fn table ->
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
    end)
  end
end
