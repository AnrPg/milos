defmodule Palee.Infrastructure.Security.RateLimiter do
  def check_rate(key, interval_ms, max) do
    impl().check_rate(key, interval_ms, max)
  end

  defp impl do
    Application.get_env(
      :palee,
      :rate_limiter,
      Palee.Infrastructure.Security.RedisRateLimiter
    )
  end
end
