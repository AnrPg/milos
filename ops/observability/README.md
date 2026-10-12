# Observability profile (TD-031 / ADR-098)

An opt-in Docker Compose profile that turns the API's telemetry into
dashboards and alerts using only free/open-source components:

| Service | Image (pinned by tag + digest) | Role |
|---|---|---|
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.161.0` | Receives OTLP traces from the API and derives HTTP rate/error/latency metrics (spanmetrics connector) |
| `prometheus` | `prom/prometheus:v3.15.0` | Scrapes the API's internal metrics listener and the collector, evaluates alert rules |
| `alertmanager` | `prom/alertmanager:v0.34.1` | Groups, de-duplicates and delivers alerts (webhook by default, optional email) |
| `grafana` | `grafana/grafana:13.2.3` | Provisioned datasource + the "Milos Training - Operations" dashboard |

Nothing here starts on a plain `docker compose up`. All four services carry
`profiles: ["observability"]`, and the API keeps its listener and trace
export switched off until you set the variables below.

## Enable it

1. In `.env`:

   ```dotenv
   # API -> collector traces
   OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
   # API internal metrics listener (Prometheus scrapes api:9568)
   METRICS_PORT=9568
   METRICS_TOKEN=<output of: openssl rand -hex 32>
   # Where alerts go
   ALERTMANAGER_WEBHOOK_URL=https://ntfy.example.com/milos-alerts
   # Grafana login
   GRAFANA_ADMIN_PASSWORD=<strong password>
   ```

2. Start (or restart) the stack with the profile:

   ```sh
   docker compose --profile observability up -d
   ```

   The API must restart to pick up `METRICS_PORT`/`OTEL_*`. In production it
   refuses to boot when `METRICS_PORT` is set without a `METRICS_TOKEN` of at
   least 32 characters.

3. Open the UIs through an SSH tunnel. They bind to `127.0.0.1` only:

   ```sh
   ssh -L 13000:127.0.0.1:13000 -L 19090:127.0.0.1:19090 -L 19093:127.0.0.1:19093 owner@server
   ```

   - Grafana: <http://127.0.0.1:13000>, folder "Milos Training"
   - Prometheus: <http://127.0.0.1:19090> (Alerts tab shows rule state)
   - Alertmanager: <http://127.0.0.1:19093> (silences, delivery status)

To turn it off, run `docker compose --profile observability stop` and clear
`METRICS_PORT`/`OTEL_EXPORTER_OTLP_ENDPOINT`.

## Exposure

- **Caddy routes none of these services.** The Caddyfile only proxies
  `/api/*` and `/socket/*` to the API and everything else to the web app.
- The API's metrics listener is a **separate Bandit server** on
  `METRICS_PORT`. It is not part of the Phoenix endpoint, so `/metrics` cannot
  be reached through `https://<site>/...`. Compose never publishes that port,
  and every scrape needs `Authorization: Bearer $METRICS_TOKEN`.
- The collector's OTLP ports (4317/4318) are only reachable on the internal
  `app` network.
- Grafana is not exposed through Caddy on purpose. Every Caddy site address is
  required, so adding an optional Grafana host would need its own
  `GRAFANA_SITE_ADDRESS`. If you want one, add a site block that
  `reverse_proxy grafana:3000` and set `GRAFANA_ROOT_URL` to match.

## Where alerts go

Alertmanager sends every alert to `ALERTMANAGER_WEBHOOK_URL` as standard
Alertmanager webhook JSON. That works with ntfy, Gotify, Matrix hookshot,
Slack/Discord/Teams bridges, n8n, or your own endpoint. The URL is written
into a private tmp file at container start (`alertmanager/entrypoint.sh`),
because Alertmanager does not read environment variables.

If the variable is empty, the container still starts and logs a warning, and
alerts stay visible in Grafana, Prometheus and the Alertmanager UI. They are
**not delivered anywhere**, and `AlertmanagerNotificationsFailing` fires.

Routing: critical alerts repeat every 1h, warnings every 4h, info every 24h. A
critical alert hides its own warning tier for the same `signal`/`queue` (for
example, outbox critical hides outbox warning).

**Email instead of (or as well as) the webhook:**

1. In `alertmanager/alertmanager.yml`, uncomment the `smtp_*` globals and the
   `email` receiver, then set `route.receiver: email`, or add a child route.
2. Put the SMTP password in `.env` as `ALERTMANAGER_SMTP_PASSWORD`. It is
   rendered to `/tmp/alertmanager-smtp-password`, which
   `smtp_auth_password_file` reads.
3. `docker compose --profile observability up -d alertmanager`.

## What is measured

The API exports these through `MilosTrainingWeb.Telemetry.prometheus_metrics/0`:

| Signal (TD-031) | Metric | Source |
|---|---|---|
| HTTP rate / 5xx / p95 (from traces) | `traces_span_metrics_calls_total`, `traces_span_metrics_duration_milliseconds_*` | OTLP traces -> spanmetrics |
| HTTP latency per route (in-app) | `milos_http_request_duration_seconds`, `milos_http_exceptions_total` | Phoenix telemetry |
| Readiness failures | `milos_readiness_check_up{dependency}`, `milos_readiness_failures_total{failed}` | 30s readiness probe + `/api/health` |
| Outbox age | `milos_outbox_oldest_due_seconds{queue}`, `milos_outbox_pending_jobs`, `milos_outbox_retryable_jobs` | 30s probe over due Oban jobs |
| Auth anomalies | `milos_auth_anomalies_total{reason}`, `milos_rate_limit_rejections_total{bucket}` | Fallback controller, Guardian error handler, rate limiter |
| Cache invalidation | `milos_cache_operations_total{cache,operation,result}` | Landing cache (Redis) |
| Upload rejections | `milos_upload_rejections_total{context,reason}` | Upload validation/verification |
| Oban failures | `milos_oban_job_failures_total{queue,worker,state}`, `milos_oban_job_completions_total`, `milos_oban_job_duration_seconds` | Oban telemetry |
| Runtime | `milos_vm_memory_bytes`, `milos_vm_run_queue`, `milos_repo_query_duration_seconds`, `milos_repo_queue_duration_seconds` | BEAM / Ecto |

The structured `telemetry_summary=` log line (TelemetryLogReporter) keeps
working without this profile. It now also carries outbox age, readiness probe
results and rate-limit rejections.

## Alert thresholds

All rules are in `prometheus/rules/milos-alerts.yml`. Unit tests for the
boundaries are in `prometheus/tests/milos-alerts.test.yml`.

| Alert | Threshold | Why |
|---|---|---|
| `MilosApiMetricsDown` (critical) | scrape fails 2m | API down or token mismatch; every other API alert goes blind |
| `MilosReadinessDependencyDown` (critical) | a dependency reports down for 2m | `/api/health` returns 503 and Compose marks the API unhealthy. 2m rides out restarts |
| `MilosReadinessFailuresRecurring` (warning) | > 5 failed evaluations / 10m | Health checks run every 10s, so 5 failures is about 1 minute of cumulative flapping |
| `MilosHttp5xxRateCritical` / `Elevated` | 5xx > 5% for 5m / > 2% for 15m, with at least 0.1 req/s | A small gym's traffic is spiky; the traffic floor stops one failed request at night from paging |
| `MilosHttpLatencyP95Critical` / `High` | p95 > 2.5s for 10m / > 1s for 15m | Interactive API calls should take well under 1s; 2.5s is noticeably broken on mobile |
| `MilosOutboxBacklogCritical` / `Aging` | oldest due job > 15m / > 5m, for 5m | Healthy queues drain in seconds; 15m-old notifications and invalidations are user-visible |
| `MilosOutboxRetryBacklog` | > 20 retryable jobs for 15m | A downstream dependency (push, search, storage) keeps failing |
| `MilosObanJobsDiscarded` | any discard in 15m | Discarded means attempts are exhausted; the side effect is lost until someone acts |
| `MilosObanFailureRateHigh` | > 20% failures with at least 5 failures / 15m, for 10m | Retries normally absorb transient failures; sustained 20% is systemic |
| `MilosCredentialFailuresSpike` | > 50 failed logins / 10m | Far above what a few hundred members produce by mistyping; looks like credential stuffing |
| `MilosRefreshTokenRejectionsSpike` | > 20 / 10m | Token replay or a broken client release |
| `MilosCredentialEndpointRateLimited` | > 10 / 10m | Credential endpoints allow 10 req/min per client, so repeated hits mean automated traffic |
| `MilosCacheInvalidationFailing` | failures persisting 5m | Stale data is bounded by the 60s TTL, but Redis is degraded |
| `MilosCacheReadsBypassed` | > 50% of reads miss Redis for 10m | Every landing request is falling through to PostgreSQL |
| `MilosUploadRejectionsSpike` | > 20 / 15m | Normal users trigger a handful of rejections; more points to a client bug or abuse |
| `MilosUploadVerificationFailing` | > 3 missing/unverified / 15m | Usually MinIO, bucket policy or CORS/public-endpoint misconfiguration |
| `MilosOtelCollectorDown` / `MilosTracesNotArriving` | collector down 5m / no traces for 12h | Trace-derived alerts are blind (`OTEL_EXPORTER_OTLP_ENDPOINT` unset?) |
| `AlertmanagerNotificationsFailing`, `PrometheusRuleEvaluationFailing` | sustained failures | The alerting pipeline itself is broken |

`invalid_token` and `unauthenticated` auth anomalies are mostly expired
access tokens on their way to a refresh. They are on the dashboard for
context but deliberately do not alert.

## Validating changes

The repository does not ship these binaries. Use the official release
tarballs, or run them through `docker run` with the same image tags:

```sh
promtool check config --syntax-only ops/observability/prometheus/prometheus.yml
promtool check rules ops/observability/prometheus/rules/milos-alerts.yml
promtool test rules ops/observability/prometheus/tests/milos-alerts.test.yml
amtool check-config ops/observability/alertmanager/alertmanager.yml
otelcol-contrib validate --config=ops/observability/otel-collector/config.yaml
docker compose --profile observability config --quiet
```

If you rename a metric in `MilosTrainingWeb.Telemetry`, update the rules, the
rule tests and `grafana/dashboards/milos-operations.json` together.
