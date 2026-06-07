defmodule MilosTraining.Application.TokenVerifier do
  def decode_refresh_token(refresh_token), do: impl().decode_refresh_token(refresh_token)
  def user_from_claims(claims), do: impl().user_from_claims(claims)

  defp impl do
    Application.fetch_env!(:milos_training, :token_verifier)
  end
end
