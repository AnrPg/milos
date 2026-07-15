# ADR-040: Package Entitlements and Allowance Ledger
Date: 2026-07-15
Status: Accepted

## Context
Finance currently derives a coarse entitlement status from membership,
subscription, and invoice state. Scheduling and Execution reject blocked or
inactive managed memberships, but the pure policy ignores the requested
capability. Active and grace memberships therefore receive every product
channel, class visits are not limited, coaching delivery is not measured, and
accounts without a Finance profile remain unmanaged indefinitely.

Membership packages already carry generic `params`, and package subscriptions
snapshot those params. The missing contract is a validated meaning for those
snapshots plus concurrency-safe allowance accounting. Counting bookings or
executions immediately before a write is insufficient: concurrent requests can
both observe the final available unit, and later rejection, withdrawal,
attendance, role transition, or slot deletion cannot be reconciled reliably.

Administrators also need to grant additional class visits or coaching
touchpoints to one person from that person's admin profile without mutating the
shared package or silently rewriting its historical snapshot.

## Decision
Finance owns a versioned package entitlement plan and an append-only allowance
ledger.

Package `params` contain an `entitlement_version`, explicit delivery `channels`,
explicit `capabilities`, and named `allowances`. Package family and tags remain
descriptive metadata and never imply authorization. Subscription
`params_snapshot` remains the immutable effective package contract.

The initial channels are `in_person`, `workout_library`,
`personal_programming`, and `coach_messaging`. The initial capabilities are
`book_classes`, `execute_class_workouts`, `execute_library_workouts`,
`execute_assigned_workouts`, and `receive_coaching_touchpoints`. Allowances use
an integer limit or `unlimited` and an explicit `calendar_week`,
`calendar_month`, or `subscription_period` boundary.

Finance records allowance changes in `finance_entitlement_usage_entries`.
Reservation, finalization, release, direct consumption, and administrative
adjustment are append-only events with idempotency keys and source references.
The effective subscription is locked while a limited allowance is checked and
reserved, preventing concurrent oversubscription.

Cross-context use cases use reservation sagas. An Application service reserves
Finance allowance, performs the owning-context write, then finalizes or releases
the reservation. A reconciliation worker releases abandoned reservations.
Scheduling, Execution, Workouts, and Messaging never import Finance schemas.

Class booking reserves one class visit while pending or approved. Rejection and
eligible withdrawal release it; attendance finalizes it. Class workout
execution reuses the booking entitlement and does not consume a second visit.
Assigned, class, and self-selected execution use distinct channel/capability
requests after their source relationship has been authenticated.

Coaching allowance counts explicit service units rather than arbitrary chat
messages. `programming_delivery` and an explicitly marked `coach_check_in` are
countable touchpoints; ordinary chat remains unmetered.

Per-user extensions are Finance-owned append-only administrative adjustments.
An admin may add units for a named allowance and period from the unified admin
user profile, with a required reason and idempotency key. Extensions do not add
missing channels or capabilities. Repeated personal exceptions are represented
as dated override grants and are revoked by compensating entries, never by
rewriting package snapshots or deleting history.

Rollout is controlled by `observe`, `enforce_managed`, and `enforce_all` modes.
Admin actors explicitly bypass customer Finance entitlement checks. Before
`enforce_all`, an idempotent backfill application service creates migrated
member/athlete profiles, assigns approved legacy packages, and imports active
future reservations through public bounded-context APIs.

## Rationale
The entitlement plan makes packages an explicit product contract instead of
inferring behavior from names or tags. Immutable subscription snapshots prevent
later package edits from changing benefits already sold.

An append-only ledger follows the audit model already established by Finance
credits and payment reversals. Row locking inside the Finance adapter provides a
single concurrency boundary, while application-level compensation preserves
bounded-context ownership.

Personal grants belong beside Finance usage rather than on Scheduling bookings
or user identity. They remain visible, attributable, reversible, and scoped to
one allowance period without forking the package catalog.

## Alternatives Considered
Counting Scheduling and Execution records at authorization time was rejected
because it races and cannot represent pending reservations or compensations.

Storing mutable `remaining_visits` columns was rejected because corrections,
period resets, and audit history become ambiguous.

Inferring benefits from package family or tags was rejected because renaming or
classification changes would silently alter access.

Mutating a user's package snapshot for personal exceptions was rejected because
it destroys the commercial contract and makes renewals unpredictable.

Charging every coaching chat message was rejected because message count is not
a meaningful unit of coaching service and would discourage useful
communication.

Allowing missing Finance profiles permanently was rejected because it prevents
TD-017 from ever reaching complete enforcement. A staged, observable backfill
provides compatibility without making the bypass permanent.

## Consequences
Package create/update contracts become strict and generated frontend types must
be regenerated. Existing packages without a valid plan remain observable during
rollout but must be remediated before `enforce_all`.

Booking resolution, withdrawal, attendance, slot deletion, assignment creation,
coaching delivery, execution start, and role transition gain Finance
orchestration. Compensation and idempotency are mandatory because the bounded
contexts intentionally do not share a transaction.

The member and admin read models expose effective capabilities, allowance
limits, committed/reserved usage, personal extensions, remaining units, and
reset dates. Realtime user-scoped invalidations refresh these views without
polling.

## Implementation Notes
### Phase 1 — Finance foundation

The package contract is parsed by pure `EntitlementPlan` and `AllowancePeriod`
modules with closed atom vocabularies; no package input is converted into a new
runtime atom. Existing packages without `entitlement_version` remain storable
during the observe rollout, while any package that declares a version is
strictly validated.

Allowance extensions are represented as negative `adjustment` deltas. Normal
reserve/consume/release facts therefore remain independently measurable, while
effective capacity is calculated as base limit plus extensions minus committed
usage. This avoids disguising a personal grant as ordinary usage.

The adapter locks the membership/effective-subscription boundary before policy
evaluation and insert. Idempotency is checked before quota evaluation so a
retry of a successful final-unit request returns the original fact rather than
being rejected as newly exhausted.

Focused validation after Phase 1 completed with eight Domain/Finance tests and
zero failures against PostgreSQL, including plan validation, period boundaries,
rollout behavior, reservation idempotency, exhaustion, release, and an audited
one-person admin extension.

### Phase 2 — Orchestration and contracts

Booking uses a reservation saga: Finance reserves before Scheduling writes,
creation failures compensate, withdrawal/rejection release, and attendance
finalizes. Execution authenticates its source relationship before asking
Finance for the source-specific channel and capability, so class executions
reuse the booking visit rather than charging twice. Programming delivery and
explicit coach check-ins consume coaching touchpoints; normal chat remains
unmetered.

The API returns stable entitlement denial codes and exposes effective benefits
to both the current user and the unified admin dossier. Package authoring is a
closed OpenAPI contract. Personal extensions and revocations are represented by
opposite-signed adjustment facts linked through `parent_entry_id`; the original
grant is never edited or deleted.

An hourly Oban reconciliation job releases reservations older than 24 hours
that have no terminal fact. This is a safety net for process interruption, not
a replacement for synchronous compensation.

### Phase 3 — Product surfaces and rollout

The package editor now authors channels, capabilities and both initial
allowances without raw JSON. The admin user profile shows live remaining units,
reset boundaries, extension history and reason-required grant/revoke actions.
The member billing view shows the same effective contract and refreshes through
the existing user-scoped realtime invalidation event without polling.

Legacy rollout is an idempotent cross-context Application service with a shared
dry-run/apply classifier. It validates mapped packages before mutation, creates
only missing member/athlete Finance profiles, assigns only accounts without an
active subscription, reports unmapped/failing accounts, and is safe to repeat.
The admin package screen exposes readiness and apply controls. Existing active
subscriptions are deliberately preserved rather than silently rewritten.

Validation completed with 10 focused entitlement/backfill tests and the full
backend suite (375 tests, zero failures), frontend ESLint, `tsc --noEmit`, and a
production Next.js build. The development migration was also exercised against
PostgreSQL before live-flow verification. No TD-017 implementation work was
deferred.
