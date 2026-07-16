defmodule MilosTraining.Repo.Migrations.AddMessagingMessageSequence do
  use Ecto.Migration

  def change do
    alter table(:messaging_messages) do
      add :sequence_number, :bigserial, null: false
    end

    create unique_index(:messaging_messages, [:sequence_number])
    create index(:messaging_messages, [:thread_id, :sequence_number])
  end
end
