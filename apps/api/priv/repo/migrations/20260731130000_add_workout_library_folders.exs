defmodule MilosTraining.Repo.Migrations.AddWorkoutLibraryFolders do
  use Ecto.Migration

  def change do
    create table(:workout_folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :parent_id, references(:workout_folders, type: :binary_id, on_delete: :restrict)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps()
    end

    create index(:workout_folders, [:parent_id])
    create index(:workout_folders, [:created_by_id])

    create unique_index(:workout_folders, [:parent_id, :name],
             where: "parent_id IS NOT NULL",
             name: :workout_folders_parent_name_index
           )

    create unique_index(:workout_folders, [:name],
             where: "parent_id IS NULL",
             name: :workout_folders_root_name_index
           )

    alter table(:master_workouts) do
      add :folder_id, references(:workout_folders, type: :binary_id, on_delete: :nilify_all)

      add :source_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:master_workouts, [:folder_id])
    create index(:master_workouts, [:source_workout_id])
  end
end
