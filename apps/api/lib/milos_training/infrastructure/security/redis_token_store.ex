defmodule MilosTraining.Infrastructure.Security.RedisTokenStore do
  @prefix "auth:refresh:revoked:"

  def revoke(nil, _ttl_ms), do: {:error, :invalid_jti}
  def revoke(_jti, ttl_ms) when ttl_ms <= 0, do: {:error, :invalid_ttl}

  def revoke(jti, ttl_ms) do
    case Redix.command(:redix, ["SET", key(jti), "1", "PX", Integer.to_string(ttl_ms)]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def revoked?(nil), do: {:error, :invalid_jti}

  def revoked?(jti) do
    case Redix.command(:redix, ["EXISTS", key(jti)]) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  def consume(nil, _ttl_ms), do: {:error, :invalid_jti}
  def consume(_jti, ttl_ms) when ttl_ms <= 0, do: {:error, :invalid_ttl}

  def consume(jti, ttl_ms) do
    case Redix.command(:redix, [
           "SET",
           key(jti),
           "1",
           "PX",
           Integer.to_string(ttl_ms),
           "NX"
         ]) do
      {:ok, "OK"} -> {:ok, true}
      {:ok, nil} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp key(jti), do: @prefix <> jti
end
