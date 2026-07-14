defmodule MilosTraining.Repo.Migrations.AddProgressStateToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add(:status, :string, null: false, default: "active")
      add(:current_segment_index, :integer, null: false, default: 0)
      add(:segment_started_at_utc, :utc_datetime_usec)
      add(:paused_elapsed_ms, :integer, null: false, default: 0)
      add(:resume_countdown_ends_at_utc, :utc_datetime_usec)
    end
  end
end
