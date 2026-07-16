defmodule MilosTraining.Repo.Migrations.AddMessagingUserForeignKeys do
  use Ecto.Migration

  def change do
    alter table(:messaging_threads) do
      modify :created_by_id, references(:users, type: :binary_id, on_delete: :nothing),
        from: :binary_id
    end

    alter table(:messaging_participants) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :nothing),
        from: :binary_id,
        null: false

      modify :last_read_message_id,
             references(:messaging_messages, type: :binary_id, on_delete: :nilify_all),
             from: :binary_id
    end

    alter table(:messaging_messages) do
      modify :sender_id, references(:users, type: :binary_id, on_delete: :nothing),
        from: :binary_id,
        null: false
    end
  end
end
