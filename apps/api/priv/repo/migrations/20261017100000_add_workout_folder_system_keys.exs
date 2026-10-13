defmodule MilosTraining.Repo.Migrations.AddWorkoutFolderSystemKeys do
  use Ecto.Migration

  # System folders (Athletes, Classes, per-athlete and per-day class folders) are
  # created and found by a stable key, so coaches can rename or move them freely.
  # Root folder names were also unique across *all* organizations; they are now
  # unique per organization so every gym can have its own "Athletes"/"Classes".
  def up do
    alter table(:workout_folders) do
      add :system_key, :string
    end

    create unique_index(:workout_folders, [:organization_id, :system_key],
             where: "system_key IS NOT NULL",
             name: :workout_folders_organization_system_key_index
           )

    drop_if_exists index(:workout_folders, [:name], name: :workout_folders_root_name_index)

    create unique_index(:workout_folders, [:organization_id, :name],
             where: "parent_id IS NULL",
             name: :workout_folders_root_name_index
           )
  end

  def down do
    drop_if_exists index(:workout_folders, [:organization_id, :name],
                     name: :workout_folders_root_name_index
                   )

    create unique_index(:workout_folders, [:name],
             where: "parent_id IS NULL",
             name: :workout_folders_root_name_index
           )

    drop_if_exists index(:workout_folders, [:organization_id, :system_key],
                     name: :workout_folders_organization_system_key_index
                   )

    alter table(:workout_folders) do
      remove :system_key
    end
  end
end
