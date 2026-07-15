defmodule MilosTraining.Repo.Migrations.CreateAssignmentMessages do
  use Ecto.Migration

  def change do
    create table(:assignment_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :assigned_workout_id,
          references(:assigned_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sender_id, :binary_id, null: false
      add :sender_nickname, :string, null: false
      add :body, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:assignment_messages, [:assigned_workout_id, :inserted_at])
  end
end
