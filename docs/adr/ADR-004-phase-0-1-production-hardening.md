# ADR-004: Phase 0 and 1 Production Hardening
Date: 2026-06-05
Status: Accepted

## Context
The first implementation slices for project scaffold and authentication are
functionally present, but the production-readiness audit found several gaps:
proxy-unaware auth rate limiting, refresh rotation failure semantics that can
invalidate a session on transient errors, incomplete contract documentation,
localhost-biased deployment defaults, and a frontend auth console that is not
durable enough for a production auth flow.

## Decision
Harden Phase 0 and Phase 1 by making proxy-aware rate limiting part of the
endpoint pipeline, changing refresh rotation to avoid revoking the current
refresh token until replacement token issuance succeeds, tightening public
error semantics, documenting real endpoint behaviors in OpenAPI, and adding a
durable frontend session surface for the implemented auth slice.

## Rationale
These changes fix correctness and operability issues without widening scope
beyond the scaffold and auth slices. They preserve the existing bounded
context/application-service split while reducing production risk in the only
implemented user-facing flow.

## Alternatives Considered
Leaving the current slice as-is and deferring hardening was rejected because
the identified issues can cause cross-user rate limiting, incorrect 401/429
responses during infrastructure incidents, and refresh-token loss. Replacing
JWT auth entirely was rejected because Guardian remains aligned with the
approved stack and only needs flow hardening, not replacement.

## Consequences
The API now depends more explicitly on reverse-proxy header trust and clearer
error handling. The frontend auth slice remains intentionally limited to
in-memory session handling until a secure cookie-based transport exists, which
keeps the slice safer but means reloads clear auth state. Contract artifacts
and tests must stay aligned with the hardened behavior.

## Implementation Notes
Phase 0 production defaults now accept an overridable `PHX_HOST` in Compose,
and the web container explicitly targets the API container for server-side
proxying. This removes the localhost-only deployment assumption from the
initial scaffold without changing the public local-development defaults.

Phase 1 now restores client IPs from trusted proxy headers before rate
limiting, keeps auth infrastructure failures distinct from user-auth failures,
and rotates refresh tokens without revoking the old token before replacement
token issuance succeeds.

The auth frontend now keeps the implemented session strictly in memory,
surfaces structured validation errors, and no longer overstates the phase as a
fully verified product surface.

The rate limiter now has deterministic unit coverage for rolling-window
behavior across boundary conditions, and the repo includes a committed
`.env.example` so Phase 0 bootstrap no longer depends on undocumented local
environment variables.

Readiness checks now sit behind an injectable infrastructure adapter so the
health contract is testable and can continue to represent dependency state
without coupling controller tests to live Redis behavior. The reverse-proxy
configuration now explicitly forwards scheme and host headers to Phoenix so the
TLS-terminated Caddy deployment path is unambiguous.

The identity user-store boundary now returns plain identity account structs
instead of leaking Ecto schemas directly into application/auth flows. The
Ecto-backed adapter remains the persistence implementation, but the exposed
boundary is closer to the bounded-context contract defined in the design doc.

OpenAPI artifacts were regenerated after the controller/spec changes so the
generated TypeScript client matches the implemented contract.

The Phase 0 development and release boot path now installs Oban's required
database tables through a first-class repo migration. That keeps the Docker
stack aligned with the approved architecture, where background job
infrastructure is present in the scaffold rather than silently disabled when
the app boots.

Local Docker host ports now default to an isolated Milos-specific high-port
range instead of common service defaults such as 80, 443, 3000, 4000, 6379,
7700, and 9000. That reduces accidental collisions with other local projects
while keeping every exposed port explicitly overridable through `.env`.

The API endpoint now applies explicit CORS approval for the Milos web origins
used in local development and proxy mode, including the direct Next.js host
port and the Caddy HTTP/HTTPS entrypoints. This keeps browser-based service
communication inside the project working without opening the API to arbitrary
origins.

The web auth slice now persists the issued auth tokens locally and restores
the session on refresh by revalidating the access token or rotating from the
stored refresh token when needed. Guarded pages redirect unauthenticated
visitors to `/login`, and the root route is now a minimal authenticated
landing page rather than the raw auth console.

Development bootstrap now ensures an admin account exists through the seed
script so the implemented admin workout-management routes are directly
reachable in the browser without manual database intervention.

## Production Security Amendment — 2026-07-15

The earlier local token-persistence choice is superseded by ADR-003's cookie
refresh and in-memory access-token protocol. Production web responses use a
per-request nonce Content Security Policy, authenticated caches are private,
versioned and TTL-bounded, and authorization failures evict matching cached
responses. MinIO has explicit internal and public endpoints, matching runtime
credentials, health-gated startup, and a separately routed public media origin.

Container publication is part of the verified delivery graph: immutable commit
tags may be pushed only after backend tests/static checks, frontend checks,
generated-contract diffing, migration rollback verification, and image builds
for the same commit succeed.
