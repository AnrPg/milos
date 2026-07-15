# TD-017 Package Entitlements — Three-Phase Implementation Plan

**Goal:** Enforce package channels, capabilities, class-visit quotas, coaching
touchpoint allowances, strict Finance-profile rollout, and audited per-user
allowance extensions across every hexagonal layer.

**Architecture:** Finance owns pure entitlement semantics and allowance facts.
Finance infrastructure serializes reservations. Cross-context Application
services coordinate reservation sagas. Controllers remain translation-only and
are preceded by OpenAPI contracts. Frontend consumers use generated operation
types and realtime invalidation.

## Phase 1 — Finance Domain and Persistence

- [x] Re-read design §2 and ADR-016, ADR-017, ADR-022, ADR-029, ADR-031, ADR-040.
- [x] Write ADR-040 and add it to the ADR index before implementation code.
- [x] Write failing pure tests for entitlement-plan validation, capability
      mapping, rollout modes, period boundaries, allowance limits, and admin
      bypass.
- [x] Implement pure `EntitlementPlan`, `AllowancePeriod`, and expanded
      `EntitlementPolicy` modules.
- [x] Add migrations and Ecto schemas for append-only allowance usage and
      Finance enforcement settings.
- [x] Add Finance port callbacks, adapter operations, CQRS commands/queries,
      public context functions, locking, idempotency, and concurrency tests.
- [x] Extend Finance member/effective-entitlement read models with plan, usage,
      personal grants, remaining units, and reset dates.
- [x] Run focused Domain and Finance integration tests.
- [x] Update ADR-040 implementation notes for Phase 1 and commit atomically.

## Phase 2 — Cross-Context Use Cases and API Contracts

- [x] Re-read the booking, execution, assignment, messaging, attendance, and
      role-transition sections of the design and accepted ADRs.
- [x] Integrate reservation/finalization/release with submit, resolve, withdraw,
      attendance, slot deletion, and role transition Application services.
- [x] Resolve execution source before applying source-specific Finance channel
      and capability authorization; prevent double consumption for class
      execution.
- [x] Meter programming delivery and explicit coach check-ins through top-level
      Application services without cross-context schema imports.
- [x] Add strict OpenAPI entitlement schemas and endpoints before controller
      actions, including structured machine-readable denials and admin grants.
- [x] Add reservation reconciliation worker and user-scoped Finance
      invalidations.
- [x] Add Application integration, ConnCase, idempotency, compensation, and
      concurrent-final-unit tests.
- [x] Run focused and full backend verification.
- [x] Update ADR-040 implementation notes for Phase 2 and commit atomically.

## Phase 3 — Frontend, Backfill, Rollout, and Completion

- [x] Re-read admin profile, member Finance, responsiveness, accessibility, and
      realtime requirements.
- [x] Regenerate OpenAPI JSON and TypeScript schema; do not edit generated files.
- [x] Replace touched handwritten Finance wrappers with generated operation
      types.
- [x] Add typed package entitlement controls to package create/edit UI.
- [x] Add an `Entitlements & Allowances` section to the unified admin user
      profile, including one-person extension, required reason, period, expiry,
      history, and revocation/compensation visibility.
- [x] Add member/athlete benefit and allowance usage presentation plus clear
      booking/execution denial guidance.
- [x] Add realtime entitlement query invalidation without polling.
- [x] Implement idempotent dry-run/apply legacy backfill and enforcement-mode
      readiness reporting.
- [x] Run frontend lint/type-check/build, backend full suite, migration checks,
      and manual live flows for limited, unlimited, overridden, legacy, and
      exhausted accounts.
- [x] Mark TD-017 resolved, finish ADR-040 Implementation Notes, and document
      only genuinely deferred follow-up work.
- [x] Commit in small dependency-ordered semantic groups and push only after all
      verification passes.
