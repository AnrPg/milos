defmodule MilosTraining.Repo.Migrations.HardenMessagingThreads do
  use Ecto.Migration

  def change do
    alter table(:messaging_threads) do
      add :direct_key, :string, size: 73
    end

    create unique_index(:messaging_threads, [:direct_key],
             name: :messaging_threads_direct_key_index
           )

    create index(:messaging_messages, [:thread_id, :inserted_at, :id],
             name: :messaging_messages_thread_order_index
           )
  end
end
