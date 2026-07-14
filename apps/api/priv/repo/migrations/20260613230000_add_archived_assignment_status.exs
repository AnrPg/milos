defmodule MilosTraining.Repo.Migrations.AddArchivedAssignmentStatus do
  use Ecto.Migration

  def up do
    drop constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check)

    create constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check,
             check:
               "athlete_status IS NULL OR athlete_status IN ('accepted', 'rejected', 'archived')"
           )
  end

  def down do
    execute(
      "UPDATE assigned_workout_athletes SET athlete_status = 'rejected' WHERE athlete_status = 'archived'"
    )

    drop constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check)

    create constraint(:assigned_workout_athletes, :assigned_workout_athletes_athlete_status_check,
             check: "athlete_status IS NULL OR athlete_status IN ('accepted', 'rejected')"
           )
  end
end
