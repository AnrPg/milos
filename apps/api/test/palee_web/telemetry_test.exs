defmodule PaleeWeb.TelemetryTest do
  # Not async: emits global telemetry events and swaps the readiness checker.
  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Observability.{MetricsPlug, PrometheusExporter}
  alias Palee.TestSupport.TelemetryCapture
  alias PaleeWeb.Telemetry

  describe "prometheus_metrics/0" do
    setup do
      name = Module.concat(__MODULE__, "Exporter#{System.unique_integer([:positive])}")
      start_supervised!({PrometheusExporter, name: name, metrics: Telemetry.prometheus_metrics()})
      {:ok, exporter: name}
    end

    test "exports every TD-031 signal group with bounded labels", %{exporter: exporter} do
      emit_representative_events()

      output = exporter |> PrometheusExporter.scrape() |> IO.iodata_to_binary()

      for expected <- [
            ~s(palee_http_request_duration_seconds_bucket{method="GET",route="/api/td031",status_class="5xx",le="0.25"}),
            ~s(palee_http_exceptions_total{route="/api/td031"}),
            ~s(palee_readiness_failures_total{failed="redis,search"}),
            ~s(palee_readiness_check_up{dependency="redis"} 0),
            ~s(palee_outbox_oldest_due_seconds{queue="td031"} 75),
            ~s(palee_outbox_pending_jobs{queue="td031"} 3),
            ~s(palee_outbox_retryable_jobs{queue="td031"} 1),
            ~s(palee_auth_anomalies_total{reason="invalid_credentials"}),
            ~s(palee_rate_limit_rejections_total{bucket="credentials"}),
            ~s(palee_cache_operations_total{cache="landing",operation="invalidate",result="error"}),
            ~s(palee_upload_rejections_total{context="invoice",reason="document_too_large"}),
            ~s(palee_oban_job_failures_total{queue="td031",state="discard",worker="TD031.Worker"}),
            ~s(palee_oban_job_completions_total{queue="td031",state="success",worker="TD031.Worker"}),
            ~s(palee_oban_job_duration_seconds_count{queue="td031"}),
            # Repo query events are only rendered by type here: emitting a fake
            # one would crash (and detach) OpentelemetryEcto's global handler.
            "# TYPE palee_repo_query_duration_seconds histogram",
            "palee_vm_memory_bytes 1024"
          ] do
        assert output =~ expected, "missing #{expected} in:\n#{output}"
      end
    end
  end

  describe "ADR-192 revenue and shop metrics" do
    setup do
      name = Module.concat(__MODULE__, "ShopExporter#{System.unique_integer([:positive])}")
      start_supervised!({PrometheusExporter, name: name, metrics: Telemetry.prometheus_metrics()})
      {:ok, exporter: name}
    end

    test "count revenue by stream and shop activity with folded labels", %{exporter: exporter} do
      alias Palee.Finance.RevenueTelemetry
      alias Palee.Shop.Observability

      RevenueTelemetry.payment_recorded("shop", 2_500)
      RevenueTelemetry.refund_recorded("shop", 500)
      RevenueTelemetry.payment_recorded("not-a-stream", 100, "euros")
      Observability.order_placed(:online, 2_500)
      Observability.order_paid("pos", :cash, 2_500)
      Observability.order_refunded("pos", 500)
      Observability.stock_moved("sale", -2)
      Observability.low_stock(:low)

      Observability.reconciliation_checked(%{
        days: [%{}, %{}],
        drifted: [%{drift_cents: 7}],
        drift_cents: 7
      })

      output = exporter |> PrometheusExporter.scrape() |> IO.iodata_to_binary()

      for expected <- [
            ~s(palee_revenue_recorded_cents_total{stream="shop",currency="EUR"} 2500),
            ~s(palee_revenue_refunded_cents_total{stream="shop",currency="EUR"} 500),
            ~s(palee_revenue_recorded_cents_total{stream="other",currency="XXX"} 100),
            ~s(palee_revenue_payments_total{stream="shop"} 1),
            ~s(palee_shop_orders_placed_total{channel="online"} 1),
            ~s(palee_shop_orders_paid_total{channel="pos",method="cash"} 1),
            ~s(palee_shop_refunded_cents_total{channel="pos"} 500),
            ~s(palee_shop_stock_units_moved_total{kind="sale"} 2),
            ~s(palee_shop_low_stock_alerts_total{status="low"} 1),
            ~s(palee_shop_reconciliation_runs_total{result="drift"} 1),
            ~s(palee_shop_reconciliation_drift_cents 7)
          ] do
        assert output =~ expected, "missing #{expected} in:\n#{output}"
      end
    end
  end

  describe "emit_readiness_measurements/0" do
    setup do
      previous = Application.fetch_env!(:palee, :readiness_checker)

      Application.put_env(
        :palee,
        :readiness_checker,
        Palee.TestSupport.FakeReadinessError
      )

      on_exit(fn -> Application.put_env(:palee, :readiness_checker, previous) end)
      TelemetryCapture.capture([[:palee, :readiness, :check]])
    end

    test "emits an up gauge per dependency" do
      assert :ok = Telemetry.emit_readiness_measurements()

      assert_received {:telemetry_event, [:palee, :readiness, :check], %{up: 1},
                       %{dependency: "database"}}

      assert_received {:telemetry_event, [:palee, :readiness, :check], %{up: 0},
                       %{dependency: "redis"}}
    end
  end

  describe "children/1" do
    test "starts no exporter or listener unless the metrics port is configured" do
      ids = [enabled: false] |> Telemetry.children(start_oban: false) |> child_ids()

      refute PrometheusExporter in ids
      refute Bandit in ids
      refute :palee_outbox_probe in ids
    end

    test "starts the exporter, probes and an internal listener when enabled" do
      children =
        Telemetry.children([enabled: true, port: 9568, ip: {0, 0, 0, 0}, token: "t"],
          start_oban: true
        )

      ids = child_ids(children)

      assert PrometheusExporter in ids
      assert :palee_readiness_probe in ids
      assert :palee_outbox_probe in ids

      bandit = Enum.find(children, &(child_id(&1) == Bandit))
      {Bandit, options} = bandit
      assert options[:port] == 9568
      assert options[:ip] == {0, 0, 0, 0}
      assert options[:plug] == {MetricsPlug, [token: "t"]}
    end

    test "polls outbox age whenever Oban runs so log summaries include it" do
      ids = [enabled: false] |> Telemetry.children(start_oban: true) |> child_ids()

      assert :palee_outbox_probe in ids
      refute PrometheusExporter in ids
    end
  end

  defp child_ids(children), do: Enum.map(children, &child_id/1)

  defp child_id(%{id: id}), do: id
  defp child_id({module, _options}) when is_atom(module), do: module
  defp child_id(module) when is_atom(module), do: module

  defp emit_representative_events do
    conn = %Plug.Conn{method: "GET", status: 503}
    duration = System.convert_time_unit(200, :millisecond, :native)

    :telemetry.execute([:phoenix, :router_dispatch, :stop], %{duration: duration}, %{
      conn: conn,
      route: "/api/td031"
    })

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: duration}, %{
      conn: conn,
      route: "/api/td031",
      kind: :error,
      reason: :boom
    })

    :telemetry.execute([:palee, :readiness, :failure], %{count: 1}, %{
      failed: %{search: %{status: :error}, redis: %{status: :error}}
    })

    :telemetry.execute([:palee, :readiness, :check], %{up: 0}, %{dependency: "redis"})

    :telemetry.execute(
      [:palee, :outbox, :age],
      %{oldest_seconds: 75, pending: 3, retryable: 1},
      %{queue: "td031"}
    )

    :telemetry.execute([:palee, :auth, :anomaly], %{count: 1}, %{reason: "invalid_credentials"})
    :telemetry.execute([:palee, :rate_limit, :rejected], %{count: 1}, %{bucket: "credentials"})

    :telemetry.execute([:palee, :cache, :state], %{count: 1, keys: 2}, %{
      cache: "landing",
      operation: "invalidate",
      result: "error"
    })

    :telemetry.execute([:palee, :upload, :rejected], %{count: 1}, %{
      context: "invoice",
      reason: :document_too_large
    })

    job = %Oban.Job{queue: "td031", worker: "TD031.Worker"}

    :telemetry.execute([:oban, :job, :exception], %{duration: duration}, %{
      job: job,
      state: :discard
    })

    :telemetry.execute([:oban, :job, :stop], %{duration: duration}, %{job: job, state: :success})

    :telemetry.execute([:palee, :runtime], %{memory_bytes: 1024, run_queue: 0}, %{})
  end
end
