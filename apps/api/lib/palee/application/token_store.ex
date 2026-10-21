defmodule Palee.Application.TokenStore do
  @behaviour Palee.Application.Ports.TokenStore

  @impl true
  def revoke(jti, ttl_ms), do: impl().revoke(jti, ttl_ms)

  @impl true
  def revoked?(jti), do: impl().revoked?(jti)

  @impl true
  def consume(jti, ttl_ms), do: impl().consume(jti, ttl_ms)

  defp impl do
    Application.fetch_env!(:palee, :token_store)
  end
end
