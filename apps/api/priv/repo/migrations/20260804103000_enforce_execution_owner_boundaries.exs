defmodule MilosTraining.Repo.Migrations.EnforceExecutionOwnerBoundaries do
  use Ecto.Migration

  @tables ~w(workout_executions execution_progress_operations)

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
