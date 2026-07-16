defmodule MilosTraining.Repo.Migrations.CreateExecutionProgressOperations do
  use Ecto.Migration

  def change do
    create table(:execution_progress_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :operation_id, :binary_id, null: false

      add :execution_id,
          references(:workout_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :base_version, :integer, null: false
      add :result_version, :integer, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:execution_progress_operations, [:execution_id, :user_id, :operation_id],
             name: :execution_progress_operations_idempotency_index
           )

    create index(:execution_progress_operations, [:inserted_at])
  end
end
