# ADR-044: Verifiable delivery, observability, and web quality gates
Date: 2026-07-15
Status: Accepted

## Context
Backend and frontend builds exist, but publication is not gated on the complete
quality signal. The frontend has no unit/component/integration/E2E coverage;
generated contract artifacts are duplicated; accessibility-sensitive overlays
lack a common dialog primitive; telemetry defines metrics without a production
reporter; logging is mostly prose; deployment variables and OpenAPI generation
are under-documented; and PWA install/update behavior is incomplete.

## Decision
Adopt a single verifiable delivery and operations contract:

1. Vitest, Testing Library, axe, and Playwright cover pure logic,
   components, API integration, accessibility, offline execution, auth rotation,
   timers, chat acknowledgement, and critical finance/admin flows.
2. A shared accessible dialog primitive owns focus trapping, focus restoration,
   `aria-modal`, labelling, inert background behavior, and Escape handling.
3. `openapi.json` is the only contract source. Generated TypeScript output has
   one canonical location; stale duplicates are removed. CI regenerates and
   fails on diff. Handwritten API wrappers progressively consume generated
   operation types without weakening contract generation.
4. Ship an installable manifest, complete icon set, stable service-worker
   registration route, explicit update-available UX, authenticated-cache TTL,
   and offline mutation reconciliation.
5. OpenTelemetry exports Phoenix/Bandit request traces and Ecto query traces
   through OTLP when an endpoint is configured. Local/dev/test default to
   no-export mode while retaining structured telemetry summaries and readiness
   checks. Logs carry request/job/user-safe correlation identifiers. Scheduled
   measurements, Oban failures, outbox age, auth anomalies, cache state, upload
   rejection, and dependency readiness are emitted in machine-readable form for
   dashboards/alert thresholds.
6. CI runs backend precommit/Credo/tests/xref architecture rules, frontend
   format/lint/type/unit/component/E2E accessibility checks, npm audit policy,
   OpenAPI generation diff, migration up/down/up verification, Compose config,
   and Docker builds before immutable commit-tag publication.
7. Deployment documentation and `.env.example` enumerate Caddy site/email,
   MinIO internal/public endpoints, CSP/reporting, OTLP, database, Redis,
   Meilisearch, and secret requirements. ADR/debt indices are validated for
   unique numbers, existing files, statuses, and links.

## Rationale
A deployable image should be evidence that the exact commit passed its complete
verification graph. Automated browser and accessibility coverage protects state
machines that type checking cannot validate. Standard telemetry and structured
logs make retryable asynchronous architecture operable rather than opaque.
Generated-contract and documentation checks prevent silent source-of-truth
drift.

## Alternatives Considered
- Keeping image publication in a separate push workflow was rejected because
  timing and branch state cannot prove verification of the same commit.
- Snapshot-heavy frontend tests were rejected in favor of behavioral tests and
  a small number of visual E2E assertions.
- Console-only telemetry was rejected because it provides no production
  aggregation, alerting, or cross-service correlation.
- Allowing two generated TypeScript schemas was rejected because consumers can
  compile against different contracts.

## Consequences
- CI is slower but parallel jobs keep feedback bounded; publication is safer.
- Frontend test and observability dependencies are added intentionally and
  pinned through lockfiles.
- Production deployment can export OTLP traces by setting standard OTEL
  endpoint variables; local and test environments intentionally default to
  no-export mode.
- Accessibility and PWA behavior become release-blocking contracts.

## Implementation Notes
Implemented 2026-07-16.

- Added `vitest`, Testing Library, `jsdom`, Playwright, `@axe-core/playwright`,
  and MSW to the web package. The first committed suites cover offline
  execution check-off rebase semantics, Phoenix push acknowledgement/error
  propagation, and the shared modal focus trap.
- Added Playwright desktop and mobile smoke coverage for `/about` and
  `/register`, with API refresh/theme calls stubbed so public accessibility
  checks do not require a live backend. The test uses an isolated
  `.next-playwright` dist directory because the local `.next` cache may be
  container-owned, and it retries one axe injection when Next dev destroys the
  execution context during first-load navigation churn.
- Added an accessible heading to the auth console so registration/login has a
  stable page landmark and the browser smoke has an intentional assertion point.
- Added OpenTelemetry packages for OTLP trace export plus Phoenix/Bandit and
  Ecto instrumentation. Application startup attaches the instrumentation before
  the supervision tree starts. Runtime config exports only when
  `OTEL_EXPORTER_OTLP_ENDPOINT` or `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is set;
  otherwise traces are explicitly disabled.
- Updated `.env.example` with OTEL service and endpoint variables. The existing
  structured telemetry log reporter remains the local/default metrics path.
- CI now runs frontend unit tests and Playwright accessibility smoke before web
  builds and before Gitea image publication. Image publication remains gated on
  source verification.
- Verification performed after implementation: `npm run test`, `npm run
  type-check`, `npm run lint`, `npm run test:e2e`, `mix compile
  --warnings-as-errors`, `mix milos.architecture`, and `mix credo --strict
  --format oneline`.
