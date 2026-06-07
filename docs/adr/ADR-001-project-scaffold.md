# ADR-001: Project Scaffold and Monorepo Structure
Date: 2026-06-05
Status: Accepted

## Context
This project starts from a near-empty repository and needs a baseline
structure that supports a Phoenix API, a Next.js frontend, and the
supporting local infrastructure required by the design doc. The initial
decision also needs to choose a deployment shape for local development and
self-hosted production, plus the default reverse proxy.

## Decision
Use a single repository with `apps/api` for the Phoenix backend and
`apps/web` for the Next.js frontend. Use Docker Compose as the local and
initial deployment orchestrator, and use Caddy as the reverse proxy and TLS
terminator.

## Rationale
The expected scale in the design doc does not justify Kubernetes or a more
distributed deployment model. A monorepo keeps architecture docs, backend,
frontend, and deployment files versioned together and makes phase-based
delivery easier to coordinate. Docker Compose matches the self-hosted,
operationally simple target. Caddy reduces certificate-management overhead
compared with a manual reverse-proxy setup.

## Alternatives Considered
An Elixir umbrella app was rejected because the frontend is a separate
Next.js application and tighter coupling would not help the intended
architecture. Separate repositories were rejected because cross-app changes,
shared CI, and documentation would become harder to coordinate. Nginx was
rejected because it adds manual TLS lifecycle work. Traefik was rejected
because it introduces more proxy-specific configuration than this project
needs initially.

## Consequences
The repository becomes a single delivery unit for backend, frontend, and
infrastructure definitions. Compose files and service contracts must stay in
sync as the system grows. Branding-facing metadata should stay easy to rename
because the human-approved placeholder name may change later.

## Implementation Notes
Phase 0 implementation uses the confirmed brand name `Milos Training` in
branding-facing files where appropriate, while keeping the Phoenix OTP app
name as `milos_training` to stay aligned with the approved design doc and later
phases.

The repository already had a `.git` directory on `main`, so Phase 0 reused
that baseline instead of re-running `git init`.

The Next.js build path was switched to `next build --webpack` because the
default Turbopack build path attempted behavior that was not reliable in the
current execution environment. This keeps the scaffold buildable without
changing the application architecture.
