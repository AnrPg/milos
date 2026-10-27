defmodule Palee.Application.PRSearchIndex do
  @behaviour Palee.Application.Ports.PRSearchIndex

  @impl true
  def enqueue_upsert(pr), do: impl().enqueue_upsert(pr)
  @impl true
  def enqueue_delete(id, owner_user_id), do: impl().enqueue_delete(id, owner_user_id)
  @impl true
  def search(user_id, query), do: impl().search(user_id, query)
  @impl true
  def replace_documents(prs), do: impl().replace_documents(prs)

  defp impl, do: Application.fetch_env!(:palee, :pr_search_index)
end
