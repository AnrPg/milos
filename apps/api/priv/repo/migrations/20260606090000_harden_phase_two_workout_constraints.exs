defmodule MilosTraining.Repo.Migrations.HardenPhaseTwoWorkoutConstraints do
  use Ecto.Migration

  def up do
    alter table(:master_workouts) do
      modify :created_by_id, references(:users, type: :binary_id, on_delete: :nothing),
        null: false
    end

    drop_if_exists index(:workout_sections, [:master_workout_id, :parent_section_id, :order])

    create unique_index(:workout_sections, [:master_workout_id, :order],
             where: "parent_section_id IS NULL",
             name: :workout_sections_root_order_index
           )

    create unique_index(:workout_sections, [:master_workout_id, :parent_section_id, :order],
             where: "parent_section_id IS NOT NULL",
             name: :workout_sections_child_order_index
           )

    create unique_index(:workout_sections, [:id, :master_workout_id],
             name: :workout_sections_id_master_workout_id_index
           )

    drop constraint(:workout_sections, "workout_sections_parent_section_id_fkey")

    execute(
      """
      ALTER TABLE workout_sections
      ADD CONSTRAINT workout_sections_parent_same_workout_fkey
      FOREIGN KEY (parent_section_id, master_workout_id)
      REFERENCES workout_sections(id, master_workout_id)
      ON DELETE SET NULL
      """,
      """
      ALTER TABLE workout_sections
      DROP CONSTRAINT workout_sections_parent_same_workout_fkey
      """
    )
  end

  def down do
    execute(
      """
      ALTER TABLE workout_sections
      ADD CONSTRAINT workout_sections_parent_section_id_fkey
      FOREIGN KEY (parent_section_id)
      REFERENCES workout_sections(id)
      ON DELETE SET NULL
      """,
      """
      ALTER TABLE workout_sections
      DROP CONSTRAINT workout_sections_parent_section_id_fkey
      """
    )

    drop_if_exists index(:workout_sections, [:id, :master_workout_id],
                     name: :workout_sections_id_master_workout_id_index
                   )

    drop_if_exists index(:workout_sections, [:master_workout_id, :parent_section_id, :order],
                     name: :workout_sections_child_order_index
                   )

    drop_if_exists index(:workout_sections, [:master_workout_id, :order],
                     name: :workout_sections_root_order_index
                   )

    create unique_index(:workout_sections, [:master_workout_id, :parent_section_id, :order])

    alter table(:master_workouts) do
      modify :created_by_id, :binary_id, null: false
    end
  end
end
