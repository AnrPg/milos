#!/bin/sh
# Alertmanager cannot expand environment variables in its config, so
# secrets/destinations are rendered into private tmp files before start-up.
set -eu
umask 077

if [ -n "${ALERTMANAGER_WEBHOOK_URL:-}" ]; then
  printf '%s' "$ALERTMANAGER_WEBHOOK_URL" > /tmp/alertmanager-webhook-url
else
  echo "observability: ALERTMANAGER_WEBHOOK_URL is empty; alerts are visible in Grafana/Alertmanager but NOT delivered anywhere" >&2
  # Unroutable placeholder keeps the config valid; deliveries fail and
  # AlertmanagerNotificationsFailing fires on the dashboard.
  printf '%s' "http://127.0.0.1:9/alert-destination-not-configured" > /tmp/alertmanager-webhook-url
fi

if [ -n "${ALERTMANAGER_SMTP_PASSWORD:-}" ]; then
  printf '%s' "$ALERTMANAGER_SMTP_PASSWORD" > /tmp/alertmanager-smtp-password
fi

exec /bin/alertmanager "$@"
