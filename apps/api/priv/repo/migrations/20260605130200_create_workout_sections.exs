defmodule MilosTraining.Repo.Migrations.CreateWorkoutSections do
  use Ecto.Migration

  def change do
    create table(:workout_sections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :parent_section_id,
          references(:workout_sections, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, null: false
      add :order, :integer, null: false
      add :scoreable, :boolean, null: false, default: false
      add :score_config, :map
      add :timer_config, :map

      timestamps(updated_at: false)
    end

    create index(:workout_sections, [:master_workout_id])
    create index(:workout_sections, [:parent_section_id])
    create unique_index(:workout_sections, [:master_workout_id, :parent_section_id, :order])
  end
end
