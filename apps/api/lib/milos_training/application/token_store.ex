defmodule MilosTraining.Application.TokenStore do
  @behaviour MilosTraining.Application.Ports.TokenStore

  @impl true
  def revoke(jti, ttl_ms), do: impl().revoke(jti, ttl_ms)

  @impl true
  def revoked?(jti), do: impl().revoked?(jti)

  @impl true
  def consume(jti, ttl_ms), do: impl().consume(jti, ttl_ms)

  defp impl do
    Application.get_env(
      :milos_training,
      :token_store,
      MilosTraining.Infrastructure.Security.RedisTokenStore
    )
  end
end
