#!/bin/sh
# Prometheus cannot expand environment variables inside scrape configs, so the
# API scrape token is rendered into a private tmp file before start-up.
set -eu

if [ -z "${METRICS_TOKEN:-}" ]; then
  echo "observability: METRICS_TOKEN is empty; the milos-api scrape will be rejected (401) and MilosApiMetricsDown will fire" >&2
fi

umask 077
printf '%s' "${METRICS_TOKEN:-}" > /tmp/milos-metrics-token

exec /bin/prometheus "$@"
