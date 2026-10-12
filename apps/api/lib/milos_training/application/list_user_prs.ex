defmodule MilosTraining.Application.ListUserPRs do
  alias MilosTraining.Application.PRSearchIndex
  alias MilosTraining.Pantheon

  def call(user_or_context, opts \\ [])

  # Owner-only under RLS: runs in the acting user's scope (ADR-111).
  def call(%{user_id: user_id} = context, opts) when is_list(opts),
    do: Pantheon.with_user_context(context, fn -> call(user_id, opts) end)

  def call(user_id, opts) do
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
