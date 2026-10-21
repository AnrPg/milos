defmodule Palee.Application.TokenVerifier do
  def decode_refresh_token(refresh_token), do: impl().decode_refresh_token(refresh_token)
  def user_from_claims(claims), do: impl().user_from_claims(claims)

  defp impl do
    Application.fetch_env!(:palee, :token_verifier)
  end
end
