defmodule MilosTraining.Repo.Migrations.ScopeAssignmentUniquenessToNotes do
  use Ecto.Migration

  def change do
    drop_if_exists(
      unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for],
        name: :assigned_workouts_master_workout_id_scheduled_for_index
      )
    )

    create unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :admin_notes],
             name: :assigned_workouts_workout_date_notes_index,
             nulls_distinct: false
           )
  end
end
