defmodule MilosTraining.Repo.Migrations.AddMessageClientOperationId do
  use Ecto.Migration

  def change do
    alter table(:messaging_messages) do
      add :client_operation_id, :uuid
    end

    create unique_index(:messaging_messages, [:sender_id, :client_operation_id],
             name: :messaging_messages_sender_client_operation_id_index
           )
  end
end
