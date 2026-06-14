defmodule MilosTraining.Repo.Migrations.CreateMessagingThreads do
  use Ecto.Migration

  def change do
    create table(:messaging_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :context_type, :string, null: false
      add :context_id, :binary_id
      add :created_by_id, :binary_id

      timestamps(updated_at: false)
    end

    create unique_index(:messaging_threads, [:context_type, :context_id],
             where: "context_type != 'direct'",
             name: :messaging_threads_context_unique
           )
  end
end
