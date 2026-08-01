defmodule MilosTraining.Repo.Migrations.AllowWorkoutAssignmentPerSeriesOccurrence do
  use Ecto.Migration

  def change do
    alter table(:class_series) do
      modify :master_workout_id, :binary_id, null: true
    end

    alter table(:scheduled_classes) do
      modify :master_workout_id, :binary_id, null: true
    end
  end
end
