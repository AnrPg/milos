defmodule MilosTraining.Infrastructure.Auth.GuardianTokenIssuer do
  @behaviour MilosTraining.Application.Ports.TokenIssuer

  alias MilosTraining.Infrastructure.Auth.Guardian

  # F-20/P3.5: the "memberships" claim was embedded in every token and never
  # read back - not for authorization (TenantContext is always rebuilt from
  # live DB state per request) and not by the client. Removed rather than kept
  # fresh through reissuance: a stale claim nobody consults is an invitation
  # for someone to start trusting it later, and it put the user's full list of
  # organizations and roles into a credential that gets logged and stored.
  @impl true
  def issue_pair(user) do
    claims = %{"sv" => user.security_version || 1}

    with {:ok, access_token, _} <- Guardian.encode_and_sign(user, claims, token_type: "access"),
         {:ok, refresh_token, _} <-
           Guardian.encode_and_sign(user, claims, token_type: "refresh") do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end
end
