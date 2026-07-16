defmodule MilosTraining.Application.PRSearchIndex do
  @behaviour MilosTraining.Application.Ports.PRSearchIndex

  @impl true
  def enqueue_upsert(pr), do: impl().enqueue_upsert(pr)
  @impl true
  def enqueue_delete(id), do: impl().enqueue_delete(id)
  @impl true
  def search(user_id, query), do: impl().search(user_id, query)

  defp impl, do: Application.fetch_env!(:milos_training, :pr_search_index)
end
