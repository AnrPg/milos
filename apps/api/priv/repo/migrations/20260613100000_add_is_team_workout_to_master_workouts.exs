defmodule MilosTraining.Repo.Migrations.AddIsTeamWorkoutToMasterWorkouts do
  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      add :is_team_workout, :boolean, default: false, null: false
    end
  end
end
