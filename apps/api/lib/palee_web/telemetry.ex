defmodule PaleeWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  alias Palee.Application.Readiness

  alias Palee.Infrastructure.Observability.{
    MetricsPlug,
    OutboxProbe,
    PrometheusExporter,
    TelemetryLogReporter
  }

  @probe_period 30_000

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    prometheus = Application.get_env(:palee, :prometheus_metrics, enabled: false)
    start_oban = Application.get_env(:palee, :start_oban, true)

    prometheus
    |> children(start_oban: start_oban)
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc """
  Supervision children. The outbox probe runs whenever Oban runs so the
  structured log summary always carries outbox age. The Prometheus exporter,
  the readiness probe and the internal metrics listener only start when
  `METRICS_PORT` enables them (ADR-116); nothing is exposed otherwise.
  """
  def children(prometheus, options) do
    [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryLogReporter, report_interval: 60_000}
    ] ++
      outbox_probe(Keyword.fetch!(options, :start_oban)) ++
      prometheus_children(Map.new(prometheus))
  end

  defp outbox_probe(false), do: []

  defp outbox_probe(true) do
    [probe_poller(:palee_outbox_probe, {OutboxProbe, :measure, []})]
  end

  defp prometheus_children(%{enabled: true} = config) do
    [
      {PrometheusExporter, metrics: prometheus_metrics()},
      probe_poller(:palee_readiness_probe, {__MODULE__, :emit_readiness_measurements, []}),
      {Bandit,
       plug: {MetricsPlug, [token: config.token]},
       scheme: :http,
       ip: config.ip,
       port: config.port,
       startup_log: false}
    ]
  end

  defp prometheus_children(_disabled), do: []

  defp probe_poller(name, measurement) do
    Supervisor.child_spec(
      {:telemetry_poller,
       name: name, measurements: [measurement], period: @probe_period, init_delay: @probe_period},
      id: name
    )
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("palee.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("palee.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("palee.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("palee.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("palee.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  @http_buckets [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
  @job_buckets [0.05, 0.1, 0.5, 1, 5, 10, 30, 60, 300]
  @db_buckets [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5]

  @doc """
  Metrics exported in Prometheus format by `PrometheusExporter` (ADR-116).
  Every label is bounded: routes are router patterns, reasons/buckets are
  fixed atoms, workers are module names. Alert rules and Grafana dashboards in
  `ops/observability/` depend on these names; rename them together.
  """
  def prometheus_metrics do
    http_metrics() ++
      readiness_metrics() ++
      outbox_metrics() ++
      security_and_cache_metrics() ++
      job_metrics() ++ runtime_metrics() ++ revenue_metrics() ++ shop_metrics()
  end

  # ADR-192: money in and out per revenue stream. `stream` and `currency`
  # are closed lists (Palee.Finance.RevenueTelemetry folds anything else).
  # Event-level counters: the exact per-business figures are the reports
  # and the reconciliation.
  defp revenue_metrics do
    [
      sum("palee.finance.revenue.recorded.amount_cents",
        tags: [:stream, :currency],
        description: "Paid payment amounts recorded, in cents, by revenue stream",
        reporter_options: [prometheus_name: "palee_revenue_recorded_cents_total"]
      ),
      sum("palee.finance.revenue.refunded.amount_cents",
        tags: [:stream, :currency],
        description: "Refunded amounts recorded, in cents, by revenue stream",
        reporter_options: [prometheus_name: "palee_revenue_refunded_cents_total"]
      ),
      counter("palee.finance.revenue.recorded.count",
        tags: [:stream],
        description: "Paid payments recorded, by revenue stream",
        reporter_options: [prometheus_name: "palee_revenue_payments_total"]
      ),
      counter("palee.finance.revenue.refunded.count",
        tags: [:stream],
        description: "Refunds recorded, by revenue stream",
        reporter_options: [prometheus_name: "palee_revenue_refunds_total"]
      )
    ]
  end

  # ADR-192: the shop's orders, stock and revenue reconciliation
  # (Palee.Shop.Observability is the event contract).
  defp shop_metrics do
    [
      counter("palee.shop.order.placed.count",
        tags: [:channel],
        description: "Shop orders placed, by channel (online pickup or desk)",
        reporter_options: [prometheus_name: "palee_shop_orders_placed_total"]
      ),
      counter("palee.shop.order.paid.count",
        tags: [:channel, :method],
        description: "Shop orders paid, by channel and payment method",
        reporter_options: [prometheus_name: "palee_shop_orders_paid_total"]
      ),
      sum("palee.shop.order.paid.amount_cents",
        tags: [:channel],
        description: "Shop order amounts paid, in cents",
        reporter_options: [prometheus_name: "palee_shop_paid_cents_total"]
      ),
      counter("palee.shop.order.refunded.count",
        tags: [:channel],
        description: "Shop order refunds, by channel",
        reporter_options: [prometheus_name: "palee_shop_refunds_total"]
      ),
      sum("palee.shop.order.refunded.amount_cents",
        tags: [:channel],
        description: "Shop order amounts refunded, in cents",
        reporter_options: [prometheus_name: "palee_shop_refunded_cents_total"]
      ),
      counter("palee.shop.stock.movement.count",
        tags: [:kind],
        description: "Stock ledger movements, by kind",
        reporter_options: [prometheus_name: "palee_shop_stock_movements_total"]
      ),
      sum("palee.shop.stock.movement.quantity",
        tags: [:kind],
        measurement: &abs(&1.quantity),
        description: "Units moved through the stock ledger, by kind",
        reporter_options: [prometheus_name: "palee_shop_stock_units_moved_total"]
      ),
      counter("palee.shop.stock.low.count",
        tags: [:status],
        description: "Variants that crossed into low, critical or out of stock",
        reporter_options: [prometheus_name: "palee_shop_low_stock_alerts_total"]
      ),
      counter("palee.shop.reconciliation.checked.count",
        event_name: [:palee, :shop, :reconciliation, :checked],
        tags: [:result],
        description: "Shop revenue reconciliation runs, by result (ok or drift)",
        reporter_options: [prometheus_name: "palee_shop_reconciliation_runs_total"]
      ),
      sum("palee.shop.reconciliation.checked.drifted_days",
        description: "Business days found drifting by the shop revenue reconciliation",
        reporter_options: [prometheus_name: "palee_shop_reconciliation_drifted_days_total"]
      ),
      last_value("palee.shop.reconciliation.checked.drift_cents",
        description: "Absolute drift, in cents, found by the latest reconciliation run",
        reporter_options: [prometheus_name: "palee_shop_reconciliation_drift_cents"]
      )
    ]
  end

  defp http_metrics do
    [
      distribution("phoenix.router_dispatch.stop.duration",
        unit: {:native, :second},
        tags: [:method, :route, :status_class],
        tag_values: &http_tags/1,
        description: "Phoenix request latency by route pattern and status class",
        reporter_options: [
          prometheus_name: "palee_http_request_duration_seconds",
          buckets: @http_buckets
        ]
      ),
      counter("palee.http.exception.count",
        event_name: [:phoenix, :router_dispatch, :exception],
        tags: [:route],
        description: "Requests that raised inside the router",
        reporter_options: [prometheus_name: "palee_http_exceptions_total"]
      )
    ]
  end

  defp readiness_metrics do
    [
      counter("palee.readiness.failure.count",
        tags: [:failed],
        tag_values: &readiness_failure_tags/1,
        description: "Readiness evaluations with at least one failed dependency",
        reporter_options: [prometheus_name: "palee_readiness_failures_total"]
      ),
      last_value("palee.readiness.check.up",
        tags: [:dependency],
        description: "1 when the dependency passed the last readiness probe, else 0",
        reporter_options: [prometheus_name: "palee_readiness_check_up"]
      )
    ]
  end

  defp outbox_metrics do
    [
      last_value("palee.outbox.age.oldest_seconds",
        tags: [:queue],
        description: "Age of the oldest due-but-unexecuted outbox (Oban) job",
        reporter_options: [prometheus_name: "palee_outbox_oldest_due_seconds"]
      ),
      last_value("palee.outbox.age.pending",
        tags: [:queue],
        description: "Due outbox jobs waiting for their first execution",
        reporter_options: [prometheus_name: "palee_outbox_pending_jobs"]
      ),
      last_value("palee.outbox.age.retryable",
        tags: [:queue],
        description: "Due outbox jobs waiting for a retry after failing",
        reporter_options: [prometheus_name: "palee_outbox_retryable_jobs"]
      )
    ]
  end

  defp security_and_cache_metrics do
    [
      counter("palee.auth.anomaly.count",
        tags: [:reason],
        description: "Rejected credentials, tokens and credential-endpoint rate limits",
        reporter_options: [prometheus_name: "palee_auth_anomalies_total"]
      ),
      counter("palee.rate_limit.rejected.count",
        tags: [:bucket],
        description: "Requests rejected by rate limiting",
        reporter_options: [prometheus_name: "palee_rate_limit_rejections_total"]
      ),
      counter("palee.cache.state.count",
        tags: [:cache, :operation, :result],
        description: "Cache reads and invalidations by outcome",
        reporter_options: [prometheus_name: "palee_cache_operations_total"]
      ),
      counter("palee.upload.rejected.count",
        tags: [:context, :reason],
        description: "Upload attempts rejected by validation or storage verification",
        reporter_options: [prometheus_name: "palee_upload_rejections_total"]
      )
    ]
  end

  defp job_metrics do
    [
      counter("palee.oban.job.failure.count",
        event_name: [:oban, :job, :exception],
        tags: [:queue, :state, :worker],
        tag_values: &job_tags/1,
        description:
          "Oban job executions that failed (state=failure retries, discard is terminal)",
        reporter_options: [prometheus_name: "palee_oban_job_failures_total"]
      ),
      counter("palee.oban.job.completion.count",
        event_name: [:oban, :job, :stop],
        tags: [:queue, :state, :worker],
        tag_values: &job_tags/1,
        description: "Oban job executions that finished without raising",
        reporter_options: [prometheus_name: "palee_oban_job_completions_total"]
      ),
      distribution("oban.job.stop.duration",
        unit: {:native, :second},
        tags: [:queue],
        tag_values: &job_tags/1,
        description: "Oban job execution time",
        reporter_options: [
          prometheus_name: "palee_oban_job_duration_seconds",
          buckets: @job_buckets
        ]
      )
    ]
  end

  defp runtime_metrics do
    [
      distribution("palee.repo.query.total_time",
        unit: {:native, :second},
        description: "Ecto query time including pool queueing",
        reporter_options: [
          prometheus_name: "palee_repo_query_duration_seconds",
          buckets: @db_buckets
        ]
      ),
      distribution("palee.repo.query.queue_time",
        unit: {:native, :second},
        description: "Time spent waiting for a database connection",
        reporter_options: [
          prometheus_name: "palee_repo_queue_duration_seconds",
          buckets: @db_buckets
        ]
      ),
      last_value("palee.runtime.memory_bytes",
        description: "BEAM total memory",
        reporter_options: [prometheus_name: "palee_vm_memory_bytes"]
      ),
      last_value("palee.runtime.run_queue",
        description: "BEAM scheduler run queue length",
        reporter_options: [prometheus_name: "palee_vm_run_queue"]
      )
    ]
  end

  defp http_tags(%{conn: conn} = metadata) do
    %{
      method: conn.method,
      route: Map.get(metadata, :route, "unmatched"),
      status_class: status_class(conn.status)
    }
  end

  defp status_class(status) when is_integer(status), do: "#{div(status, 100)}xx"
  defp status_class(_status), do: "unknown"

  defp readiness_failure_tags(%{failed: failed}) when is_map(failed) do
    %{failed: failed |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.join(",")}
  end

  defp readiness_failure_tags(_metadata), do: %{failed: "unknown"}

  defp job_tags(%{job: job} = metadata) do
    %{queue: job.queue, worker: job.worker, state: to_string(Map.get(metadata, :state, ""))}
  end

  @doc "Readiness probe for the Prometheus exporter: one up/down gauge per dependency."
  def emit_readiness_measurements do
    {_status, checks} = Readiness.status()

    Enum.each(checks, fn {dependency, status} ->
      up = if ready?(status), do: 1, else: 0

      :telemetry.execute([:palee, :readiness, :check], %{up: up}, %{
        dependency: to_string(dependency)
      })
    end)
  end

  defp ready?(:ok), do: true
  defp ready?(%{status: :ok}), do: true
  defp ready?(_status), do: false

  defp periodic_measurements do
    [{__MODULE__, :emit_runtime_measurements, []}]
  end

  def emit_runtime_measurements do
    memory = :erlang.memory(:total)
    run_queue = :erlang.statistics(:run_queue)

    :telemetry.execute(
      [:palee, :runtime],
      %{memory_bytes: memory, run_queue: run_queue},
      %{}
    )
  end
end
