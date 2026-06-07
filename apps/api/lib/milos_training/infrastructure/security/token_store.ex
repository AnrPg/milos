defmodule MilosTraining.Infrastructure.Security.TokenStore do
  def revoke(jti, ttl_ms), do: impl().revoke(jti, ttl_ms)
  def revoked?(jti), do: impl().revoked?(jti)

  defp impl do
    Application.get_env(
      :milos_training,
      :token_store,
      MilosTraining.Infrastructure.Security.RedisTokenStore
    )
  end
end
