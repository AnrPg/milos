defmodule MilosTraining.Repo.Migrations.CreateMasterWorkouts do
  use Ecto.Migration

  def change do
    create table(:master_workouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :type, :string, null: false
      add :created_by_id, :binary_id, null: false

      timestamps()
    end

    create index(:master_workouts, [:type])
    create index(:master_workouts, [:created_by_id])
  end
end
