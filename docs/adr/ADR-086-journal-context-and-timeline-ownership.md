# ADR-086: Journal context and timeline ownership
Date: 2026-08-04
Status: Accepted

## Context
The journal-first redesign makes Today, Journal, and Progress the primary
personal-user experience. The existing application already owns adjacent facts in
Execution, Workouts, Scheduling, Wellbeing, Feedback, Pantheon, Gamification,
Coaching, Messaging, and Organizations. Those contexts must remain authoritative:
a completed execution, injury report, PR, booking, assignment, review, or coaching
note must not be copied into an unbounded journal table that can mutate or expose
another context's data.

Recent multi-tenant work also classifies personal history as global user-owned,
not tenant-owned. Organization membership scopes tenant operations; it does not
own a user's durable personal training memory. The first Journal migration
therefore needs an accepted ownership, authorization, projection, timezone, and
rollout contract before schema work begins.

Phase 0 review on 2026-08-04 accepts the journal implementation plan's Gates A-D.

## Decision
Add `MilosTraining.TrainingJournal` as a first-class bounded context.

`TrainingJournal` owns:

- independent and source-backed journal workouts recorded outside app-managed
  execution;
- journal-native recovery entries and personal notes;
- journal-native workout blocks, movements/tasks, performance rows, links,
  revisions, trash/suppressions, visibility metadata, shares, and grants;
- an owner-scoped timeline projection that references facts owned by other
  contexts.

`TrainingJournal` does not own:

- app-managed execution lifecycle, progress snapshots, scores, notes, or
  ADR-050 modification patches;
- Workouts prescriptions, master workouts, assignments, class WODs, or movement
  catalog ownership;
- Scheduling bookings, attendance, class slots, or booking comments;
- Wellbeing facts that remain canonical injury/body/readiness records;
- Feedback reviews, Pantheon PR facts, Gamification challenge/leaderboard facts,
  Messaging conversations, or coach-private Coaching notes.

Journal-native records, self-authored Wellbeing facts, and Pantheon PRs are
global personal resources scoped by `owner_user_id` and protected by user-scoped
RLS and grant predicates. Optional organization provenance is metadata and never
changes ownership or grants access by itself. Tenant-owned source records remain
readable only through their owning context's public APIs and only while the caller
is authorized for that source.

Today candidate composition is an Application service. It asks Execution,
Workouts, and Scheduling public APIs for plain candidate DTOs, presents candidates
without asserting completion, and persists a Journal actual only after explicit
user confirmation.

Timeline projection uses transactional local writes for TrainingJournal-owned
records and durable, idempotent projector jobs for cross-context source facts.
Projection events carry plain maps with source context/type/id, owner user,
optional organization provenance, occurrence timestamps, render snapshots, and
deep-link descriptors. Replaying a source event upserts or no-ops by
`(owner_user_id, source_context, source_type, source_id)`.

Realtime delivery is invalidation-only. REST remains the source of full payload
truth; channels emit owner-scoped `journal:changed` notifications that cause the
client to refetch.

Offline Journal commands opt in to ADR-067 only after each command has
server-side idempotency, authorization revalidation, and conflict semantics.
Create commands use `client_operation_id`; edit commands use `lock_version` and
return structured conflicts rather than silently applying last-write-wins.

Occurrence storage must persist UTC timestamp, captured IANA timezone, captured
offset, and occurrence-local date. Day grouping uses the captured local date.
Retention uses Trash for Journal-native records: hide immediately, allow restore
for 30 days, then purge owned content through a durable job. Projected source
cards use reversible personal suppression; destructive deletion is delegated to
the owning context when it exposes an authorized command.

The rollout uses reversible feature flags for personal Journal routes, Today
candidate composition, timeline projection/backfill, offline Journal commands,
and legacy surface redirects. Legacy capture surfaces remain available until
backfill, privacy, offline, and live-test evidence prove the new surfaces are
safe replacements.

## Rationale
A dedicated bounded context gives independent workouts, recovery, notes,
timeline cards, and sharing grants one coherent owner without weakening the
audit trails already owned elsewhere. It closes TD-033 directly while preserving
ADR-050's decision that app-managed execution modifications live on the
Execution aggregate.

Global personal ownership aligns with ADR-055, ADR-056, ADR-058, ADR-059, and
ADR-085: gyms and coaching organizations may see only provenance-scoped or
explicitly shared facts, while a user keeps their own training memory across
gyms, coaches, and independent use.

Durable projectors avoid noisy duplicate history while keeping source contexts
authoritative for permissions and detailed reads. REST-plus-invalidation matches
the existing realtime architecture and keeps channel payloads small and
non-authoritative.

Explicit timezone fields prevent day-boundary drift for mobile and offline
capture. Trash and suppression preserve recovery options without inventing
cross-context deletion rules.

## Alternatives Considered
Overloading `Execution` was rejected because independent or class/offline logs
that never started a timer need their own lifecycle, idempotency, sharing, and
trash rules.

Putting notes/recovery/body updates into one generic journal blob was rejected
because it loses domain meaning, weakens analytics, and duplicates Wellbeing,
Feedback, Execution, and Coaching facts.

Making Journal records tenant-owned was rejected because it would break the
approved personal-vault model and would lose history when a user leaves an
organization.

Granting coach access from an admin or owner role was rejected because
organization authority is not personal Journal consent. Coaching access requires
an accepted relationship, explicit share, or scoped access grant.

Using PubSub-only projection was rejected because source history must survive
process restarts and retries. Full event sourcing was rejected as unnecessary for
this slice.

Serving full Journal payloads over channels was rejected because REST already
owns full authorization and read-model shape; channels should only accelerate
refetch.

## Consequences
The base design bounded-context catalogue now includes
`MilosTraining.TrainingJournal`. The architecture gate must allow the context
shape before Phase 1 modules land.

Phase 1 may add only additive Journal-owned tables. Foreign keys stay inside
TrainingJournal ownership; cross-context references remain opaque IDs validated
through public contracts.

Phase 2 must define OpenAPI before controllers and must model idempotent creates,
optimistic-lock edits, timeline reads, validation failures, conflicts, visibility,
links, and trash/suppression states.

Phase 3 may need ADR-087 if projector details materially extend this decision.
Backfill and repair tooling must be idempotent, owner-scoped, observable, and
safe to replay.

TD-033 is resolved only when the standalone TrainingJournal aggregate ships.
TD-013 and TD-035 remain partly open until body/recovery capture consolidation
and offline Journal retry/remove UX ship.

## Implementation Notes
Phase 0 implementation on 2026-08-04 produced the baseline contract only:

- accepted Gates A-D from the journal implementation plan;
- added the base design context catalogue entry;
- confirmed the current architecture gate has no static bounded-context allowlist
  to edit in Phase 0;
- documented the legacy surface inventory, glossary, invariants, retention,
  export, timezone, feature-flag, and rollback assumptions in
  `docs/architecture/journal-phase-0-baseline.md`;
- did not create migrations, application modules, API contracts, controllers, or
  frontend Journal routes.
