defmodule MilosTraining.Repo.Migrations.AddDurationAdjustmentsToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      # Mid-workout clock changes by segment key;
      # see MilosTraining.Execution.Domain.DurationAdjustments.
      add :duration_adjustments, :map, null: false, default: %{}
    end
  end
end
