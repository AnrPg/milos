# ADR-003: Auth Refresh Rotation and Identity Persistence Adapters
Date: 2026-06-05
Status: Accepted

## Context
The first auth slice shipped with two gaps against the approved design doc:
refresh tokens were not rotated or revoked on use, and identity command/query
modules called `Repo` directly instead of delegating persistence into
infrastructure-layer modules. The production-readiness audit also found that
Phase 1 lacked a protected endpoint to verify JWT enforcement and lacked an
HTTP path for admin-driven role changes.

## Decision
Refresh tokens will rotate on every successful refresh and previously used
refresh token JTIs will be revoked in Redis until their original expiry.
Identity persistence will move behind context-owned infrastructure adapters,
with command/query modules depending on a context port rather than `Repo`
directly. Phase 1 will expose a protected `GET /api/auth/me` endpoint and an
admin-only `PATCH /api/admin/users/:id/role` endpoint.

## Rationale
Refresh rotation reduces the replay window for stolen refresh tokens and
aligns the implementation with the design doc’s security requirements.
Redis-backed revocation avoids introducing a second persistence mechanism for
token lifecycle state and matches the project’s approved infrastructure stack.
Moving Ecto access into infrastructure restores the strict layering rule that
the design doc requires and keeps later phases from compounding the boundary
violation.

## Alternatives Considered
Keeping stateless refresh tokens without revocation was rejected because it
does not satisfy the documented refresh-rotation requirement. Storing revoked
refresh tokens in PostgreSQL was rejected because Redis already exists in the
approved stack for ephemeral operational state and avoids schema churn for
token bookkeeping. Leaving `Repo` inside context command/query modules was
rejected because it conflicts with the repository-pattern rule in the design
doc.

## Consequences
Auth refresh now depends on Redis-backed token state in non-test environments.
Tests need an in-memory substitute for token revocation and rate-limiting
state when Redis is disabled. Identity commands and queries gain an extra
adapter layer, which adds a small amount of indirection but restores the
project’s intended architecture.

## Implementation Notes
Identity command/query modules now delegate persistence through
`MilosTraining.Identity.UserStore`, with `MilosTraining.Infrastructure.Identity.EctoUserStore`
as the production adapter. `Repo` calls no longer live in command/query
modules.

Refresh now performs `decode_and_verify` on the incoming refresh token,
checks Redis-backed revocation state for the token `jti`, revokes the used
refresh token until its original expiry, and issues a new access/refresh pair.
Tests use in-memory token-store and rate-limiter adapters so the auth suite
remains self-contained.

Phase 1 now includes a protected `GET /api/auth/me` endpoint to verify JWT
enforcement and an admin-only `PATCH /api/admin/users/:id/role` endpoint to
complete the role-management deliverable from the implementation plan.
