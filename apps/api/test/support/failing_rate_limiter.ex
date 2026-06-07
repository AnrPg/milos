defmodule MilosTraining.TestSupport.FailingRateLimiter do
  def check_rate(_key, _interval_ms, _max), do: {:error, :redis_down}
end
