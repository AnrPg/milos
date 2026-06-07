defmodule MilosTraining.Infrastructure.Security.MemoryRateLimiterTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Infrastructure.Security.MemoryRateLimiter

  setup do
    MemoryRateLimiter.reset!()
    :ok
  end

  describe "check_rate/4" do
    test "enforces a rolling window across former bucket boundaries" do
      key = "auth:login:boundary"

      assert {:ok, 1} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 1_999)
      assert {:ok, 2} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 2_000)
      assert {:error, 2} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 2_001)
    end

    test "expires attempts once they fall outside the rolling window" do
      key = "auth:login:expiry"

      assert {:ok, 1} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 1_000)
      assert {:ok, 2} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 1_100)
      assert {:ok, 2} = MemoryRateLimiter.check_rate(key, 1_000, 2, now_ms: 2_001)
    end
  end
end
