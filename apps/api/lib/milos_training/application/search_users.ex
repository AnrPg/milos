defmodule MilosTraining.Application.SearchUsers do
  alias MilosTraining.{Identity, Identity.RegistrationPolicy, Organizations}

  def call(query) do
    Identity.search_users(query)
  end

  def call(query, tenant_context) do
    tenant_context
    |> Organizations.list_active_membership_user_ids()
    |> Identity.list_by_ids()
    |> filter_query(query)
    |> Enum.sort_by(& &1.nickname)
    |> Enum.take(20)
  end

  defp filter_query(users, nil), do: users
  defp filter_query(users, ""), do: users

  defp filter_query(users, query) do
    normalized_query = RegistrationPolicy.normalize_nickname(query)

    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.nickname), normalized_query) or
        String.contains?(user.normalized_nickname || "", normalized_query)
    end)
  end
end
