defmodule MilosTraining.Application.AdminMemberSearchIndex do
  def replace_documents(documents), do: impl().replace_documents(documents)
  def search(params), do: impl().search(params)

  defp impl do
    Application.fetch_env!(:milos_training, :admin_member_search_index)
  end
end
