defmodule PaleeWeb.Plugs.RateLimitTest do
  use PaleeWeb.ConnCase, async: true

  alias Palee.TestSupport.TelemetryCapture
  alias PaleeWeb.Plugs.RateLimit

  setup do
    TelemetryCapture.capture([[:palee, :rate_limit, :rejected], [:palee, :auth, :anomaly]])
  end

  defp limited_conn(conn, opts) do
    RateLimit.call(conn, RateLimit.init(opts))
  end

  defp unique_ip, do: {10, 31, rem(System.unique_integer([:positive]), 250), 7}

  test "rejections on credential endpoints count as auth anomalies", %{conn: conn} do
    conn = %{conn | remote_ip: unique_ip(), request_path: "/api/auth/login", method: "POST"}

    refute limited_conn(conn, max: 1, interval: 60_000).halted
    assert limited_conn(conn, max: 1, interval: 60_000).status == 429

    assert_received {:telemetry_event, [:palee, :rate_limit, :rejected], %{count: 1},
                     %{bucket: "credentials"}}

    assert_received {:telemetry_event, [:palee, :auth, :anomaly], %{count: 1},
                     %{reason: "rate_limited"}}
  end

  test "named buckets are reported without raw paths or auth anomalies", %{conn: conn} do
    conn = %{conn | remote_ip: unique_ip(), request_path: "/api/search/abc", method: "GET"}
    opts = [max: 1, interval: 60_000, bucket: "search"]

    refute limited_conn(conn, opts).halted
    assert limited_conn(conn, opts).status == 429

    assert_received {:telemetry_event, [:palee, :rate_limit, :rejected], %{count: 1},
                     %{bucket: "search"}}

    refute_received {:telemetry_event, [:palee, :auth, :anomaly], _measurements, _metadata}
  end
end
