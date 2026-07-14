defmodule MilosTraining.Application.ListUserPRs do
  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex
  alias MilosTraining.Pantheon.PRStore

  def call(user_id, opts \\ []) do
    query = Keyword.get(opts, :query)

    prs =
      if query && String.trim(query) != "" do
        case MeilisearchPRIndex.search(user_id, query) do
          {:ok, ids} ->
            all = PRStore.list_user_prs(user_id)
            id_set = MapSet.new(ids)
            Enum.filter(all, &MapSet.member?(id_set, &1.id))

          {:error, _} ->
            PRStore.search_user_prs(user_id, query)
        end
      else
        PRStore.list_user_prs(user_id)
      end

    {:ok, prs}
  end
end
