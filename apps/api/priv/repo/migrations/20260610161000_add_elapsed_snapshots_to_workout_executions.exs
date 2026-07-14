defmodule MilosTraining.Repo.Migrations.AddElapsedSnapshotsToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add :total_elapsed_ms, :integer, null: false, default: 0
      add :section_elapsed_ms, :map, null: false, default: %{}
      add :segment_cycle_counts, :map, null: false, default: %{}
    end
  end
end
