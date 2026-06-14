defmodule MilosTraining.Repo.Migrations.CreateMessagingParticipants do
  use Ecto.Migration

  def change do
    create table(:messaging_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id, references(:messaging_threads, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, :binary_id, null: false
      add :last_read_message_id, :binary_id

      timestamps(updated_at: false)
    end

    create index(:messaging_participants, [:thread_id])
    create index(:messaging_participants, [:user_id])
    create unique_index(:messaging_participants, [:thread_id, :user_id])
  end
end
