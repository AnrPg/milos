defmodule MilosTraining.Workers.SyncPRSearchJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [period: 60, fields: [:worker, :args]]

  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex
  alias MilosTraining.Application.OwnershipKeys

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation" => "upsert", "pr" => pr} = args}) do
    with {:ok, _args} <- OwnershipKeys.require_user_args(args),
         true <- pr["user_id"] == args["owner_user_id"] do
      MeilisearchPRIndex.upsert_document(pr)
    else
      false -> {:error, :owner_scope_mismatch}
      error -> error
    end
  end

  def perform(%Oban.Job{args: %{"operation" => "delete", "id" => id} = args}) do
    with {:ok, _args} <- OwnershipKeys.require_user_args(args) do
      MeilisearchPRIndex.delete_document(id)
    end
  end
end
