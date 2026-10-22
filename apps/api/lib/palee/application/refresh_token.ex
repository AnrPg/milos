defmodule Palee.Application.RefreshToken do
  alias Palee.Application.TokenIssuer
  alias Palee.Application.TokenStore
  alias Palee.Application.TokenVerifier

  def call(params) when is_map(params) do
    refresh_token = Map.get(params, "refresh_token") || Map.get(params, :refresh_token)

    with {:ok, claims} <- TokenVerifier.decode_refresh_token(refresh_token),
         {:ok, user} <- TokenVerifier.user_from_claims(claims),
         {:ok, tokens} <- TokenIssuer.issue_pair(user),
         {:ok, true} <- TokenStore.consume(claims["jti"], ttl_ms(claims["exp"])) do
      {:ok, Map.put(tokens, :user, user)}
    else
      {:ok, false} ->
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
