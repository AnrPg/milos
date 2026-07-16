defmodule MilosTraining.Application.ListUserPRs do
  alias MilosTraining.Application.PRSearchIndex
  alias MilosTraining.Pantheon

  def call(user_id, opts \\ []) do
    query = Keyword.get(opts, :query)

    prs =
      if query && String.trim(query) != "" do
        case PRSearchIndex.search(user_id, query) do
          {:ok, ids} ->
            all = Pantheon.list_records(user_id)
            id_set = MapSet.new(ids)
            Enum.filter(all, &MapSet.member?(id_set, &1.id))

          {:error, _} ->
            Pantheon.search_records(user_id, query)
        end
      else
        Pantheon.list_records(user_id)
      end

    {:ok, prs}
  end
end
