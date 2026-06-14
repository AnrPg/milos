defmodule MilosTraining.Repo.Migrations.DropAssignmentMessages do
  use Ecto.Migration

  def up do
    drop table(:assignment_messages)
  end

  def down do
    create table(:assignment_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sender_id, :binary_id
      add :athlete_id, :binary_id
      add :sender_nickname, :string
      add :body, :string
      add :assigned_workout_id, references(:assigned_workouts, type: :binary_id)
      timestamps(updated_at: false)
    end
  end
end
