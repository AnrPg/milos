defmodule MilosTraining.Infrastructure.Security.RedisRateLimiter do
  @script """
  local now = tonumber(ARGV[1])
  local window_start = now - tonumber(ARGV[2])
  local max = tonumber(ARGV[3])
  redis.call("ZREMRANGEBYSCORE", KEYS[1], "-inf", window_start)
  local current = redis.call("ZCARD", KEYS[1])
  if current >= max then
    return {0, current}
  end
  redis.call("ZADD", KEYS[1], now, ARGV[4])
  redis.call("PEXPIRE", KEYS[1], ARGV[2])
  return {1, current + 1}
  """

  def check_rate(key, interval_ms, max) do
    now = System.system_time(:millisecond)
    redis_key = "rate-limit:" <> key
    member = "#{now}-#{System.unique_integer([:positive, :monotonic])}"

    case Redix.command(:redix, [
           "EVAL",
           @script,
           "1",
           redis_key,
           Integer.to_string(now),
           Integer.to_string(interval_ms),
           Integer.to_string(max),
           member
         ]) do
      {:ok, [1, count]} -> {:ok, count}
      {:ok, [0, count]} -> {:error, count}
      {:error, reason} -> {:error, reason}
    end
  end
end
