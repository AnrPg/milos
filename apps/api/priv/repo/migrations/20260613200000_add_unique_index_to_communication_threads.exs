defmodule MilosTraining.Repo.Migrations.AddUniqueIndexToCommunicationThreads do
  use Ecto.Migration

  @index_name :communication_threads_context_type_context_id_index

  def up do
    drop_if_exists index(:communication_threads, [:context_type, :context_id], name: @index_name)

    create unique_index(:communication_threads, [:context_type, :context_id], name: @index_name)
  end

  def down do
    drop_if_exists unique_index(:communication_threads, [:context_type, :context_id],
                     name: @index_name
                   )

    create index(:communication_threads, [:context_type, :context_id], name: @index_name)
  end
end
