# ADR-036: Health Check SSL Exemption
Date: 2026-07-15
Status: Accepted

## Context
Production Phoenix SSL enforcement was configured with endpoint-level
`force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]`. That correctly
redirects plain HTTP browser traffic to HTTPS when the request is not marked as
already-proxied HTTPS.

In Kubernetes deployments, however, readiness and liveness probes may call the
API pod directly over internal HTTP. When those probes do not include
`X-Forwarded-Proto: https`, the endpoint-level SSL plug redirects
`GET /api/health` to `https://milos.4kq.net/api/health` with status `301`
instead of returning the health payload. The application developer may not
control the cluster probe configuration, so relying only on Kubernetes header
changes is not enough.

## Decision
Move production SSL enforcement from Phoenix's endpoint-level `force_ssl`
setting into an explicit endpoint plug,
`MilosTrainingWeb.Plugs.ForceSslExceptHealth`, that applies `Plug.SSL` to all
paths except exactly `/api/health` when the caller is an internal/private
probe.

## Rationale
The dedicated health endpoint is operational infrastructure, not user-facing
application traffic. Letting it answer over internal HTTP allows direct pod
probes to receive a truthful `200` or `503` readiness response.

All other application routes still pass through the same `Plug.SSL` options,
including `rewrite_on: [:x_forwarded_proto]` and HSTS. External users therefore
still receive HTTPS redirects when they reach the application over plain HTTP,
including for `/api/health` when the restored remote IP is not internal/private.
Requests forwarded from an HTTPS-aware proxy continue to be treated as secure.

## Alternatives Considered
Changing Kubernetes probes to send `X-Forwarded-Proto: https` was preferred
from an infrastructure purity perspective, but rejected as the only fix because
cluster configuration is owned outside the application team.

Terminating the health check at Caddy or the ingress was rejected because it
would prove only proxy availability unless it also performed an upstream API
check. The existing `/api/health` endpoint already reports application
readiness.

Disabling SSL enforcement entirely was rejected because external users must
continue to be forced onto HTTPS in production.

## Consequences
Future production SSL changes must update the application-level
`:force_ssl` configuration instead of relying on Phoenix endpoint
`force_ssl`.

The `/api/health` route is intentionally reachable over internal HTTP from
loopback, RFC1918, and unique-local IPv6 addresses. It must remain
unauthenticated and must not expose sensitive details beyond readiness state.

## Implementation Notes
Implemented `MilosTrainingWeb.Plugs.ForceSslExceptHealth` in the endpoint plug
pipeline immediately after remote IP restoration. Production config now stores
the SSL options under `config :milos_training, :force_ssl`.

Regression tests cover the required behaviors: internal `/api/health` does not
redirect when SSL enforcement is enabled, external `/api/health` still
redirects, and a normal route such as `/api/openapi` still redirects to HTTPS.
