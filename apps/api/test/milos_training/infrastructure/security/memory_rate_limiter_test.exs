defmodule MilosTraining.Infrastructure.Security.MemoryRateLimiterTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Infrastructure.Security.MemoryRateLimiter
  alias MilosTraining.Infrastructure.Security.MemoryRateLimiter.TableOwner

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

    test "the shared table is owned by the supervised TableOwner, not a caller" do
      # This is the actual bug: ETS destroys a table when its owning process
      # exits. Before TableOwner existed, whichever process happened to call
      # check_rate/4 first (in production, a transient per-request process;
      # in this suite, intermittently a transient test/Task process) created
      # - and so owned - the table, so it could vanish the moment that
      # accidental owner exited, crashing every other concurrent caller with
      # "table identifier does not refer to an existing ETS table".
      owner_pid = Process.whereis(TableOwner)
      assert is_pid(owner_pid)
      assert :ets.info(:milos_training_rate_limits, :owner) == owner_pid
    end

    test "many transient callers can hammer the table concurrently without it dying" do
      # None of these Tasks ever owns the table (TableOwner already does, per
      # the test above), so unlike before TableOwner existed, no number of
      # them exiting mid-run can tear it down for the others.
      results =
        1..50
        |> Task.async_stream(
          fn i -> MemoryRateLimiter.check_rate("race:#{i}", 1_000, 5, now_ms: 1_000) end,
          max_concurrency: 50
        )
        |> Enum.to_list()

      assert Enum.all?(results, &match?({:ok, {:ok, 1}}, &1))
      assert :ets.whereis(:milos_training_rate_limits) != :undefined
    end
  end
end
