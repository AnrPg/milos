defmodule Palee.Infrastructure.Cache.LandingCacheTelemetryTest do
  # Redix is not started in the test environment, which exercises the
  # degraded "unavailable" path that production alerts care about most.
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Cache.LandingCache
  alias Palee.TestSupport.TelemetryCapture

  setup do
    TelemetryCapture.capture([[:palee, :cache, :state]])
  end

  test "reports invalidations that cannot reach Redis" do
    assert :ok = LandingCache.batch_invalidate([Ecto.UUID.generate()])

    assert_received {:telemetry_event, [:palee, :cache, :state], %{count: 1, keys: 1},
                     %{cache: "landing", operation: "invalidate", result: "unavailable"}}
  end

  test "does not report empty invalidation batches" do
    assert :ok = LandingCache.batch_invalidate([])

    refute_received {:telemetry_event, [:palee, :cache, :state], _measurements, _metadata}
  end

  test "reports reads that bypass the cache" do
    context = %{organization_id: Ecto.UUID.generate()}

    assert %{"ok" => true} = LandingCache.get_or_fetch(context, "user", fn -> %{"ok" => true} end)

    assert_received {:telemetry_event, [:palee, :cache, :state], %{count: 1},
                     %{cache: "landing", operation: "read", result: "unavailable"}}
  end
end
