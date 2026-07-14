defmodule MilosTraining.Repo.Migrations.AddSourceReferenceToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add :source_reference_id, :binary_id
    end

    create index(:workout_executions, [:source, :source_reference_id])
  end
end
