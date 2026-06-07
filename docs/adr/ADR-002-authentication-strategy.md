# ADR-002: Authentication Strategy
Date: 2026-06-05
Status: Accepted

## Context
Phase 1 needs a concrete authentication model for registration, login,
refresh, and role-based authorization. The implementation plan proposes
Guardian JWT with Argon2, while the architecture rules require controllers to
stay thin and delegate orchestration out of the interface layer.

## Decision
Use Guardian JWTs with Argon2 password hashing. Issue short-lived access
tokens and longer-lived refresh tokens. Route controller actions through
application services rather than invoking context logic directly from the
controller.

## Rationale
Guardian and Argon2 are already in the approved stack and fit the
self-hosted requirement. JWT keeps the API stateless for the frontend and
future mobile clients. Application-service orchestration keeps controller
logic aligned with the design doc’s layering rules.

## Alternatives Considered
Session-based authentication was rejected because the project is an API-first
split app and token auth is a cleaner fit. Rolling a custom token solution
was rejected because Guardian already covers the required lifecycle. Putting
login and registration orchestration directly in controllers was rejected
because it weakens the layer boundaries the design doc requires.

## Consequences
Auth flows now depend on token issuance and verification infrastructure.
Protected routes must use a Guardian pipeline and explicit role-check plugs.
Refresh token rotation depends on Redis-backed revocation state for used
refresh token JTIs.

## Implementation Notes
Phase 1 follows the design doc over the implementation plan where they
conflict: controllers delegate to application services instead of calling
context functions directly.

The backend namespace and OTP app were corrected to `MilosTraining` and
`:milos_training` before implementing auth so the project no longer carries
the temporary `GymApp` identity.

Oban startup is disabled in test so sandboxed database tests can run without
background peer processes fighting for ownership of test connections.

The initial audit found two production-readiness gaps in the first auth
slice: refresh tokens were only exchanged for access tokens, and auth rate
limiting used local in-memory state. Those gaps were corrected in the same
phase by introducing refresh-token rotation with Redis-backed revocation
tracking and a Redis-backed auth rate limiter, while preserving in-memory test
adapters so CI does not depend on an external Redis instance.
