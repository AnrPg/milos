defmodule MilosTraining.Repo.Migrations.CreateMessagingMessages do
  use Ecto.Migration

  def change do
    create table(:messaging_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id, references(:messaging_threads, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sender_id, :binary_id, null: false
      add :body, :text, null: false
      add :message_type, :string, null: false, default: "chat"

      timestamps(updated_at: false)
    end

    create index(:messaging_messages, [:thread_id])
    create index(:messaging_messages, [:sender_id])
    create index(:messaging_messages, [:thread_id, :inserted_at])
  end
end
