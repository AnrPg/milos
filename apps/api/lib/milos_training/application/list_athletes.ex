defmodule MilosTraining.Application.ListAthletes do
  alias MilosTraining.{Identity, Organizations}

  def call(%{organization_id: organization_id}, query) do
    organization_id
    |> active_athlete_user_ids()
    |> Identity.list_by_ids()
    |> filter_query(query)
  end

  def call(_query), do: {:error, :organization_context_required}

  defp active_athlete_user_ids(organization_id) do
    organization_id
    |> Organizations.list_active_membership_user_ids()
    |> Enum.filter(fn user_id ->
      user_id
      |> Organizations.list_memberships()
      |> Enum.any?(fn %{membership: membership, organization: organization} ->
        organization.id == organization_id and membership.role == :athlete
      end)
    end)
  end

  defp filter_query(users, query) when is_binary(query) and query != "" do
    normalized_query = String.downcase(query)

    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.nickname || ""), normalized_query)
    end)
  end

  defp filter_query(users, _query), do: users
end
