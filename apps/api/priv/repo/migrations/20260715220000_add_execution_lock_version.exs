defmodule MilosTraining.Repo.Migrations.AddExecutionLockVersion do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
