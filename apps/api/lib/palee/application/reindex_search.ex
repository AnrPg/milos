defmodule Palee.Application.ReindexSearch do
  @moduledoc """
  Rebuilds every Meilisearch index from Postgres: the admin member index and
  the per-member PR index. Run after the search store is replaced or emptied
  (`Palee.Release.reindex_search/0`). PRs are owner-only under RLS, so each
  member's are read in that member's scope.
  """

  alias Palee.Application.{AdminMemberSearchDocuments, AdminMemberSearchIndex, PRSearchIndex}
  alias Palee.{Identity, Pantheon}

  def call do
    prs = Enum.flat_map(Identity.list_all_users(), &user_prs/1)

    with :ok <- AdminMemberSearchIndex.replace_documents(AdminMemberSearchDocuments.build_all()),
         :ok <- PRSearchIndex.replace_documents(Enum.map(prs, &document/1)) do
      {:ok, %{prs: length(prs)}}
    end
  end

  defp user_prs(%{id: user_id}),
    do: Pantheon.with_user_context(%{user_id: user_id}, fn -> Pantheon.list_records(user_id) end)

  defp document(pr), do: %{id: pr.id, user_id: pr.user_id, name: pr.name}
end
