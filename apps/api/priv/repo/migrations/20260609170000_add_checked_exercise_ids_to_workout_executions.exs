defmodule MilosTraining.Repo.Migrations.AddCheckedExerciseIdsToWorkoutExecutions do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add(:checked_exercise_ids, {:array, :string}, null: false, default: [])
    end
  end
end
