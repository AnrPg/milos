defmodule MilosTraining.Workers.SyncPRSearchJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [period: 60, fields: [:worker, :args]]

  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation" => "upsert", "pr" => pr}}),
    do: MeilisearchPRIndex.upsert_document(pr)

  def perform(%Oban.Job{args: %{"operation" => "delete", "id" => id}}),
    do: MeilisearchPRIndex.delete_document(id)
end
