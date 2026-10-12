# ADR-098: Observability dashboards and alerting profile
Date: 2026-10-12
Status: Accepted

## Context
ADR-044 made the API export OTLP traces when an endpoint is configured. It
also logged a structured `telemetry_summary` line for readiness failures,
outbox age, auth anomalies, cache state, upload rejections and Oban failures.
TD-031 stayed open because nothing turned these signals into dashboards or
alerts. The application also had no metrics exporter: no OpenTelemetry metrics
SDK, no Prometheus library and no OTLP metrics pipeline. A re-audit found that
three of the claimed signals (`[:milos, :outbox, :age]`,
`[:milos, :auth, :anomaly]`, `[:milos, :cache, :state]`) were subscribed to by
the log reporter but never emitted anywhere.

The owner's constraints: self-hosted, free/open-source only, Docker Compose,
no new hex dependencies, and the default deployment must not change.

## Decision
1. Ship an opt-in Compose profile `observability` with four services, each
   pinned by exact tag and sha256 digest: OpenTelemetry Collector contrib,
   Prometheus, Alertmanager and Grafana. They have no effect unless the
   profile is enabled.
2. Derive HTTP rate, error and latency metrics from the existing OTLP traces
   with the collector's `spanmetrics` connector. Probe spans (`/metrics` and
   `/api/health`) are filtered out before aggregation.
3. Export application signals as Prometheus metrics from an in-app exporter
   built only on dependencies already in the project: `telemetry`,
   `telemetry_metrics`, `telemetry_poller`, `bandit` and `plug`.
   `MilosTraining.Infrastructure.Observability.PrometheusExporter` aggregates
   `Telemetry.Metrics` definitions into ETS with atomic counters and renders
   text format 0.0.4.
4. Serve the exporter on a separate internal Bandit listener (`METRICS_PORT`,
   conventionally 9568), not on the Phoenix endpoint. It requires a bearer
   `METRICS_TOKEN` (mandatory, at least 32 characters, in production). Compose
   never publishes that port and Caddy never proxies it.
5. Emit the missing signals: outbox age (a 30s probe over due Oban jobs), auth
   anomalies (credential/token failures, Guardian errors, credential-endpoint
   rate limits), landing-cache read/invalidation outcomes, rate-limit
   rejections, and a per-dependency readiness gauge.
6. Version concrete alert thresholds for every TD-031 signal class, with
   promtool unit tests. Alertmanager delivers to a generic webhook taken from
   `ALERTMANAGER_WEBHOOK_URL`, with a documented email option. Grafana is
   provisioned with the datasources and one operations dashboard covering all
   signal groups.

## Rationale
- Spanmetrics turns the traces we already export into RED metrics without
  touching application code, and the collector stays the single OTLP entry
  point if a trace backend is added later.
- The OpenTelemetry Erlang metrics SDK (`opentelemetry_experimental`) and the
  Prometheus client libraries are new dependencies. The brief forbids those,
  and the experimental SDK is not production-stable. `Telemetry.Metrics`
  definitions plus a small ETS reporter cover counters, gauges and histograms
  in about 300 lines that we fully test.
- A dedicated listener keeps operational data off the public origin by
  construction: even a future Caddy catch-all to the API cannot expose it.
  The token is defence in depth on the shared Docker network.
- Webhook delivery is destination-agnostic (ntfy, Gotify, Matrix, chat
  bridges, n8n), so the owner picks a channel without changing the config.

## Alternatives Considered
- **OTLP metrics push from the app**: needs `opentelemetry_experimental` (a
  new, unstable dependency). Rejected.
- **`telemetry_metrics_prometheus_core` / `prom_ex`**: new dependencies.
  Rejected under the no-new-deps rule. The exporter exposes the same text
  format, so swapping later is mechanical.
- **`/metrics` in the Phoenix router**: it would sit on the public endpoint
  behind Caddy's catch-all rules. Rejected in favour of a separate listener.
- **Parsing `telemetry_summary` logs into metrics (Loki/promtail)**: more
  moving parts, and minute-granularity aggregates are poor for alerting.
  Rejected.
- **Grafana behind Caddy**: every Caddy site address is mandatory, so an
  optional Grafana host would need a new required variable. Grafana stays on
  `127.0.0.1` (SSH tunnel), and the README shows how to add a site block.
- **Trace storage (Tempo/Jaeger)**: not in the owner's tool list. The traces
  pipeline exports only to spanmetrics, and adding a backend is one exporter
  entry.

## Consequences
- Metric names in `MilosTrainingWeb.Telemetry.prometheus_metrics/0` are now a
  contract with `ops/observability/prometheus/rules`, its tests and the
  Grafana dashboard. Renames must update all three.
- When Oban runs, the API runs one grouped `oban_jobs` query every 30s. When
  the metrics listener is enabled, it also runs a readiness probe every 30s
  (the same checks as `/api/health`).
- HTTP 5xx and latency alerts depend on `OTEL_EXPORTER_OTLP_ENDPOINT` being
  set. `MilosTracesNotArriving` flags the misconfiguration. Per-route latency
  is also available in-app (`milos_http_request_duration_seconds`) without
  tracing.
- If `ALERTMANAGER_WEBHOOK_URL` is empty, alerts are visible but not
  delivered. The container warns and `AlertmanagerNotificationsFailing`
  fires.
- Follow-ups: optional trace backend; CI job running `promtool test rules` /
  `amtool check-config` / `otelcol validate` (needs the binaries or docker in
  CI); blackbox probing of the public site from outside the host.

## Implementation Notes
Implemented 2026-10-12.

- Images: `otel/opentelemetry-collector-contrib:0.161.0`,
  `prom/prometheus:v3.15.0`, `prom/alertmanager:v0.34.1` and
  `grafana/grafana:13.2.3`. Digests are multi-arch index digests. Prometheus,
  collector and Grafana digests were confirmed against
  `registry-1.docker.io` manifests. The Alertmanager digest comes from the
  Docker Hub tag API, because the registry rate-limited the confirming HEAD
  request. Re-verify with `docker buildx imagetools inspect` before the first
  production pull.
- Validation: `otelcol-contrib validate` (0.161.0), `promtool check config
  --syntax-only`, `promtool check rules` (26 rules), `promtool test rules`
  (all boundary tests pass), `amtool check-config` (default and email
  variants), `promtool check metrics` on a real exporter scrape, and every
  dashboard expression evaluated against a live Prometheus 3.15.0. The
  collector was run locally with synthetic OTLP spans to confirm the exported
  names (`traces_span_metrics_calls_total`,
  `traces_span_metrics_duration_milliseconds_bucket`; labels `service_name`,
  `span_kind`, `http_route`, `http_response_status_code`) and that probe
  spans are dropped. `docker compose config` passes with and without the
  profile. No Docker daemon was available, so the containers themselves were
  not started.
- Compose interpolates `${VAR:?}` even for inactive profiles, which would
  break the default `docker compose up`. Required observability secrets are
  therefore enforced at container start instead: Grafana exits without
  `GRAFANA_ADMIN_PASSWORD`, and the API raises in prod when `METRICS_PORT` is
  set without `METRICS_TOKEN`. Prometheus and Alertmanager cannot read
  environment variables in their configs, so small entrypoint scripts render
  the scrape token and webhook URL into `umask 077` tmp files
  (`credentials_file` / `url_file`).
- `config/runtime.exs` now treats blank `OTEL_*`/`METRICS_*` values as unset,
  because Compose passes unset `${VAR:-}` through as empty strings.
  Previously, an empty `OTEL_EXPORTER_OTLP_ENDPOINT` would have enabled
  export to `""`.
- Handlers in the exporter rescue per-sample errors. `:telemetry` permanently
  detaches a raising handler, which would silently freeze a metric. Restarts
  detach stale handler ids before re-attaching.
- The rate limiter keys credential pipelines by raw request path, which can
  contain invitation tokens. Those rejections are reported under the fixed
  bucket label `credentials` (plus `auth_anomaly{reason="rate_limited"}`) so
  no path reaches a label.
- Guardian error types are mapped to a bounded set (`guardian_other` for
  anything unknown). `invalid_token`/`unauthenticated` are dashboard-only
  because expired access tokens produce them routinely.
- `TelemetryLogReporter` now also subscribes to readiness probe and rate-limit
  events and keeps the `operation`/`bucket` tags.
