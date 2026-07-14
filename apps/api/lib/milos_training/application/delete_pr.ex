defmodule MilosTraining.Application.DeletePR do
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex
  alias MilosTraining.Pantheon.PRStore

  def call(id, user_id) do
    case PRStore.delete_pr(id, user_id) do
      :ok ->
        Task.start(fn -> MeilisearchPRIndex.delete_document(id) end)
        InvalidateLandingPages.for_users([user_id])
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
