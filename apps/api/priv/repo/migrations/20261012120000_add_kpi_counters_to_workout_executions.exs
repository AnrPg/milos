defmodule MilosTraining.Repo.Migrations.AddKpiCountersToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      # Client-observed execution KPIs (skips, pauses, finish-wizard opens…);
      # see MilosTraining.Execution.Domain.ExecutionKpis.
      add :kpi_counters, :map, null: false, default: %{}
    end
  end
end
