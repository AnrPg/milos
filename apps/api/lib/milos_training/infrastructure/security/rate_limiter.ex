defmodule MilosTraining.Infrastructure.Security.RateLimiter do
  def check_rate(key, interval_ms, max) do
    impl().check_rate(key, interval_ms, max)
  end

  defp impl do
    Application.get_env(
      :milos_training,
      :rate_limiter,
      MilosTraining.Infrastructure.Security.RedisRateLimiter
    )
  end
end
