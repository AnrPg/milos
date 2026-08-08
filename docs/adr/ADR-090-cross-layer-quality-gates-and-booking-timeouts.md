# ADR-090: Cross-layer quality gates and booking timeouts
Date: 2026-08-08
Status: Accepted

## Context
Static-analysis, localization, accessibility, and booking-timeout checks are
release gates, but several gates are incomplete or too noisy to be trusted.
Dialyzer is not installed even though CI expects backend precommit confidence;
CI does not run a Hex advisory audit, backend Dialyzer, or the web i18n gate.
The frontend hard-coded-copy scanner treats Tailwind utility lists as user copy,
which can block releases on false positives, while catalogs can still contain
unchanged English prose in non-English locales. The public axe smoke covers only
signed-out pages and disables color contrast, so authenticated and admin routes
are not represented. Booking timeout jobs release Finance entitlement
reservations and notify admins while leaving the Scheduling booking pending,
making the persisted aggregate disagree with the side effects.

## Decision
Harden the delivery gates and booking timeout lifecycle in the owning layers:

1. Add Dialyxir as a backend quality dependency, make Dialyzer part of backend
   precommit, and run Hex advisory audit plus Dialyzer explicitly in CI.
2. Run the web i18n gate in CI and extend it with deterministic untranslated
   catalog detection that allows technical strings and proper product tokens.
3. Make the frontend hard-coded-copy scanner parse intent well enough to ignore
   utility-class strings instead of relying on path-specific exceptions.
4. Expand Playwright axe coverage to authenticated member and admin surfaces
   using stubbed API contracts, and keep WCAG AA color contrast enabled.
5. Treat booking timeout expiry as a Scheduling command that transitions the
   pending booking to the existing terminal `:cancelled` status, then let an
   Application Service orchestrate Finance release, notification dispatch, and
   realtime refresh.

## Rationale
Release gates should be both strict and quiet: false positives train operators
to bypass checks, while missing checks leave runtime and accessibility defects
undetected. Dialyzer and Hex audits are existing ecosystem gates that fit the
Phoenix app without adding a new service. Catalog quality is best enforced from
versioned message files because the product deliberately avoids a runtime UI
translation database.

Using `:cancelled` for timed-out bookings avoids a schema migration while
preserving the active-booking invariant: pending and approved bookings consume a
slot/reservation, while rejected and cancelled bookings are terminal history.
Keeping the state transition in Scheduling and the cross-context effects in an
Application Service preserves the hexagonal boundary.

## Alternatives Considered
Adding a new `:timed_out` booking enum was rejected for this pass because the
existing `:cancelled` terminal state already models expiry without a database
migration or frontend enum churn.

Excluding `organization-selector.tsx` from the i18n scanner was rejected because
it would hide future copy regressions in that component. A general utility-list
classifier is more robust.

Leaving color contrast disabled in axe was rejected because WCAG AA confidence
requires contrast to stay release-blocking.

Putting timeout state changes directly in the Oban worker was rejected because
the worker is infrastructure and should not own Scheduling aggregate rules or
cross-context orchestration.

## Consequences
CI and local precommit are slower because Dialyzer builds and checks PLTs, but
the backend now has type-contract coverage. The untranslated-catalog gate may
require deliberate translation updates when new copy is added, and future
English-like technical strings should be added only to narrowly scoped
allowances. Booking timeout history now appears as cancelled rather than
pending, freeing active-booking uniqueness and entitlement allowance in the
same observable lifecycle.

## Implementation Notes
Implemented 2026-08-08.

- Dialyxir is now a dev/test backend dependency and `mix dialyzer
  --list-unused-filters` is part of both backend precommit and CI. The PLT uses
  direct dependencies plus explicit boundary apps (`:ecto`, `:mix`,
  `:phoenix_pubsub`, `:plug`, and `:telemetry`) so the gate is practical on the
  self-hosted runner without losing type information for framework-facing code.
- The first real Dialyzer run exposed an inherited warning backlog. Those
  warnings are captured in `.dialyzer_ignore.exs`; unused-filter checking keeps
  the baseline honest and makes new warnings fail the gate. The backlog is
  tracked as TD-043.
- CI now runs `mix hex.audit`, backend Dialyzer, and the web i18n gate.
- The broader hardening slice also added the deterministic non-English catalog
  prose check, utility-class-aware UI copy scanning, expanded authenticated axe
  coverage with color contrast enabled, and Scheduling-owned timeout expiry
  through `MilosTraining.Application.TimeoutBooking`.
- Verification completed: `mix compile --warnings-as-errors`,
  `mix milos.architecture`, `mix credo --strict --format oneline`,
  `mix hex.audit`, `mix dialyzer --list-unused-filters`, targeted booking
  timeout tests, `npm run lint`, `npm run type-check`, `npm run i18n:check`,
  and `npx playwright test e2e/public-accessibility.spec.ts`.
