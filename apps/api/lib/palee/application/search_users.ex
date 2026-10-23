defmodule Palee.Application.SearchUsers do
  alias Palee.{Identity, Identity.Domain.NameSearch, Organizations}

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

  defp filter_query(users, query), do: Enum.filter(users, &NameSearch.matches?(&1, query))
end
