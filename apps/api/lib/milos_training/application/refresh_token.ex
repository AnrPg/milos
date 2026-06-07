defmodule MilosTraining.Application.RefreshToken do
  alias MilosTraining.Application.TokenIssuer
  alias MilosTraining.Application.TokenVerifier
  alias MilosTraining.Infrastructure.Security.TokenStore

  def call(params) when is_map(params) do
    refresh_token = Map.get(params, "refresh_token") || Map.get(params, :refresh_token)

    with {:ok, claims} <- TokenVerifier.decode_refresh_token(refresh_token),
         {:ok, false} <- TokenStore.revoked?(claims["jti"]),
         {:ok, user} <- TokenVerifier.user_from_claims(claims),
         {:ok, tokens} <- TokenIssuer.issue_pair(user),
         :ok <- TokenStore.revoke(claims["jti"], ttl_ms(claims["exp"])) do
      {:ok, tokens}
    else
      {:ok, true} ->
        {:error, :invalid_refresh_token}

      {:error, :token_issuance_failed} ->
        {:error, :token_issuance_failed}

      {:error, reason} when reason in [:invalid_token, :not_found] ->
        {:error, :invalid_refresh_token}

      {:error, _reason} ->
        {:error, :auth_dependency_unavailable}
    end
  end

  defp ttl_ms(exp) when is_integer(exp) do
    max((exp - System.system_time(:second)) * 1_000, 1_000)
  end

  defp ttl_ms(_exp), do: 1_000
end
