defmodule Palee.Application.AdminMemberSearchIndex do
  def replace_documents(documents), do: impl().replace_documents(documents)
  def search(params), do: impl().search(params)

  defp impl do
    Application.fetch_env!(:palee, :admin_member_search_index)
  end
end
