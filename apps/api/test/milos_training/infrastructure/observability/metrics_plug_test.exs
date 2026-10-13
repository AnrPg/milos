defmodule MilosTraining.Infrastructure.Observability.MetricsPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Telemetry.Metrics

  alias MilosTraining.Infrastructure.Observability.{MetricsPlug, PrometheusExporter}

  setup do
    name = Module.concat(__MODULE__, "Exporter#{System.unique_integer([:positive])}")

    start_supervised!(
      {PrometheusExporter,
       name: name,
       metrics: [
         counter("metrics_plug_test.probe.count",
           reporter_options: [prometheus_name: "milos_metrics_plug_probe_total"]
         )
       ]}
    )

    {:ok, exporter: name}
  end

  defp call(conn, opts), do: MetricsPlug.call(conn, MetricsPlug.init(opts))

  test "serves Prometheus text when the bearer token matches", %{exporter: exporter} do
    conn =
      conn(:get, "/metrics")
      |> Plug.Conn.put_req_header("authorization", "Bearer scrape-secret")
      |> call(exporter: exporter, token: "scrape-secret")

    assert conn.status == 200

    assert ["text/plain; version=0.0.4" <> _charset] =
             Plug.Conn.get_resp_header(conn, "content-type")

    assert conn.resp_body =~ "milos_metrics_plug_probe_total 0\n"
  end

  test "rejects missing or wrong bearer tokens", %{exporter: exporter} do
    missing = call(conn(:get, "/metrics"), exporter: exporter, token: "scrape-secret")

    wrong =
      conn(:get, "/metrics")
      |> Plug.Conn.put_req_header("authorization", "Bearer nope")
      |> call(exporter: exporter, token: "scrape-secret")

    for conn <- [missing, wrong] do
      assert conn.status == 401
      assert Plug.Conn.get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="metrics")]
      refute conn.resp_body =~ "milos_"
    end
  end

  test "serves without authentication only when no token is configured", %{exporter: exporter} do
    conn = call(conn(:get, "/metrics"), exporter: exporter, token: nil)

    assert conn.status == 200
  end

  test "serves scrapes over a dedicated Bandit listener", %{exporter: exporter} do
    server =
      start_supervised!(
        {Bandit,
         plug: {MetricsPlug, [exporter: exporter, token: "scrape-secret"]},
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    url = "http://127.0.0.1:#{port}/metrics"

    authorized = Req.get!(url, auth: {:bearer, "scrape-secret"}, retry: false)
    anonymous = Req.get!(url, retry: false)

    assert authorized.status == 200
    assert authorized.body =~ "milos_metrics_plug_probe_total 0\n"
    assert anonymous.status == 401
  end

  test "answers 404 for every other route or method", %{exporter: exporter} do
    assert call(conn(:get, "/"), exporter: exporter, token: nil).status == 404
    assert call(conn(:post, "/metrics"), exporter: exporter, token: nil).status == 404
    assert call(conn(:get, "/api/health"), exporter: exporter, token: nil).status == 404
  end
end
