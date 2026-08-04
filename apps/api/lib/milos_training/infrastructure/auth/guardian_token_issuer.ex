defmodule MilosTraining.Infrastructure.Auth.GuardianTokenIssuer do
  @behaviour MilosTraining.Application.Ports.TokenIssuer

  alias MilosTraining.Infrastructure.Auth.Guardian
  alias MilosTraining.Organizations

  @impl true
  def issue_pair(user) do
    claims = %{
      "sv" => user.security_version || 1,
      "memberships" => membership_claims(user.id)
    }

    with {:ok, access_token, _} <- Guardian.encode_and_sign(user, claims, token_type: "access"),
         {:ok, refresh_token, _} <-
           Guardian.encode_and_sign(user, claims, token_type: "refresh") do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end

  defp membership_claims(user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.map(fn %{membership: membership, organization: organization} ->
      %{
        "organization_id" => organization.id,
        "organization_slug" => organization.slug,
        "membership_id" => membership.id,
        "role" => to_string(membership.role)
      }
    end)
  end
end
