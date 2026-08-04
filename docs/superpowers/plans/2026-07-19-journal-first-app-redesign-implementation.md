# Journal-First App Redesign - Implementation Plan

**Date:** 2026-07-19  
**Status:** Ready for decision-gate review; implementation starts only after Phase 0 approval  
**Design:** `docs/superpowers/specs/2026-07-19-journal-first-app-redesign.md`  
**Base PRD:** `docs/superpowers/specs/2026-06-05-gym-app-design.md`

## Goal

Make Today and Journal the primary personal-user workflow while preserving the
canonical ownership of executions, wellbeing, feedback, PRs, coaching, scheduling,
and messaging. Deliver a simpler structured logger with independent per-set/round
actuals, source-aware prefill, a unified timeline, safe offline synchronization, and
a controlled migration away from duplicate notes/injury capture surfaces.

## Delivery Rules

Every phase follows `AGENTS.md` in this order:

- read both design documents and the phase's referenced ADRs;
- write/update the phase ADR before implementation;
- follow test-first red/green/refactor loops for non-trivial behavior;
- preserve Context -> Commands/Queries -> Store port/adapter boundaries;
- define OpenAPI before controllers and regenerate the TypeScript client;
- run `mix milos.architecture` for every backend slice;
- perform desktop and mobile live tests, including offline behavior where relevant;
- update ADR implementation notes and `docs/technical_debt.md`;
- commit atomically and in dependency order;
- request human approval before any push.

No phase may silently resolve one of the decision gates listed below.

## Decision Gates

### Gate A - TrainingJournal bounded context

**Recommendation:** accept `MilosTraining.TrainingJournal` as a first-class context.
It owns independent/source-backed journal workouts, personal notes, recovery entries,
typed links, and a timeline projection. It does not own executions, injuries,
feedback, PRs, assignments, bookings, or coach-private notes.

### Gate B - coach sharing authorization

**Recommendation:** `shared_with_coach` resolves through an explicit active coaching
relationship exposed by a public Identity/Coaching API. Admin role alone does not
grant access. Keep entries private until this contract exists.

### Gate C - independent personal users

**Recommendation:** expose Journal to every authenticated role immediately and add
independent onboarding as a capability/relationship evolution. Do not destructively
rewrite the existing role enum during this project.

### Gate D - timeline consistency

**Recommendation:** own-write transaction plus durable idempotent projector job;
cross-context plain events feed the timeline projection. Channels publish invalidation
events only; clients refetch canonical REST state.

## Phase 0 - Architecture and Product Contract

**Goal:** Turn the agreed product direction into accepted architecture boundaries and
an implementation baseline before schema work.

**Read:** base design section 2; redesign sections 1-13; ADR-009, ADR-015, ADR-029,
ADR-042, ADR-043, ADR-044, ADR-050, ADR-051, ADR-052, ADR-064, ADR-067; TD-013,
TD-033, and TD-035.

- [x] Review and accept/adjust Gates A-D with the product owner.
- [x] Write `ADR-086-journal-context-and-timeline-ownership.md` before code.
- [x] Add `TrainingJournal` to the authoritative bounded-context catalogue and
      architecture allowlists only after ADR acceptance.
- [x] Define a domain glossary: planned candidate, prescription snapshot, actual
      workout, performance row, timeline item, body update, source link, visibility.
- [x] Record invariants as executable domain-test names before migrations.
- [x] Inventory existing capture/read routes and APIs:
      `/`, `/my-workouts`, execution finish/detail, `/wellbeing`, `/reviews`, Pantheon,
      Coaching dossier, schedule/booking, and Messaging.
- [x] Produce a legacy-surface matrix with `retain`, `embed`, `redirect`, `read-only`,
      and `remove after migration` classifications.
- [x] Confirm retention/export requirements and timezone semantics.
- [x] Define rollout feature flags and rollback behavior.

**Exit criteria:** ADR-086 accepted; no unresolved ownership/privacy assumptions;
surface inventory and invariants are reviewed.

Phase 0 note: the current architecture gate pattern-scans layer paths and tenant
scope rules rather than maintaining a static bounded-context allowlist. The
authoritative design catalogue now includes `TrainingJournal`; Phase 1 must run
`mix milos.architecture` after adding the first modules.

**Commit:** `docs(journal): accept context ownership - keep canonical domains intact`

## Phase 1 - Domain Model and Additive Persistence

**Goal:** Add the journal-owned aggregate without changing existing records or routes.

**ADR:** update ADR-086 with the final relational model before migration.

### Domain tests first

- [ ] Reject workouts with no meaningful actual content.
- [ ] Generate N stable performance rows from set/round defaults.
- [ ] Preserve populated rows when a declared count decreases unless removal is
      explicitly confirmed.
- [ ] Permit different metrics/status/notes on every row.
- [ ] Validate measurement-profile-specific metrics and units.
- [ ] Preserve immutable prescription snapshots on edits.
- [ ] Validate source-link cardinality and provenance.
- [ ] Permit multiple entries per owner/day.
- [ ] Enforce private default visibility.
- [ ] Validate typed links without granting target authorization.

### Additive migrations

- [ ] Add `journal_workouts` with owner, occurrence/timezone, source/provenance,
      prescription snapshot, visibility, client operation ID, lock version, and audit
      columns.
- [ ] Add `journal_workout_blocks` with type/format/position.
- [ ] Add `journal_workout_movements` with catalog/custom identity, measurement
      profile, prescription defaults, substitution metadata, position, and notes.
- [ ] Add `journal_performance_rows` with stable sequence, kind/status, coordinates,
      typed nullable metrics, units, RPE, score, and notes.
- [ ] Add `journal_entries` for personal note and recovery records.
- [ ] Add `journal_links` for typed local/foreign references and optional movement/row
      coordinates.
- [ ] Add `journal_timeline_items` as an owner/source-unique read projection.
- [ ] Add sender/owner-scoped idempotency indexes and timeline source uniqueness.
- [ ] Use foreign keys only within TrainingJournal ownership. Cross-context IDs remain
      opaque and are checked through public contracts.

### Context implementation

- [ ] Add pure Domain policies/builders and focused unit tests.
- [ ] Add Ecto schemas and changesets.
- [ ] Define Store/Projector ports.
- [ ] Implement Ecto adapters.
- [ ] Add write-only Commands and read-only Queries.
- [ ] Expose a narrow `MilosTraining.TrainingJournal` public API.
- [ ] Add DB integration tests for idempotent create, optimistic locking, ordering,
      cascade policy, and owner scoping.
- [ ] Run migration up/down in an isolated test database; down must remove only the
      new additive structures.

**Exit criteria:** aggregate behavior is tested through the public context API; no
controller or cross-context integration exists yet; architecture gate passes.

**Commit order:** migration -> schemas -> Domain -> Commands -> Queries -> public API
and adapters, with tests committed beside each behavior.

## Phase 2 - Journal Contracts and Core API

**Goal:** Expose owner-scoped canonical writes and reads before frontend work.

- [ ] Write OpenAPI schemas for workout/block/movement/performance row, note,
      recovery, typed link, visibility, sync state, validation error, and version
      conflict.
- [ ] Define endpoints for create/read/update/delete personal entries, day/range
      timeline reads, and explicit link/keep-separate decisions.
- [ ] Define create envelopes with `client_operation_id` and edit envelopes with
      `lock_version`.
- [ ] Regenerate and commit the generated TypeScript client without manual edits.
- [ ] Add one Application Service per public use case; services contain orchestration,
      not DB queries or business rules.
- [ ] Add Phoenix controllers/router after the contract.
- [ ] Add ConnCase coverage for ownership, replay, invalid units, stale versions,
      private visibility, pagination, timezone boundaries, and multiple same-day
      workouts.
- [ ] Document journal channel invalidation events in the realtime contract.
- [ ] Emit user-scoped `journal:changed` only after a successful canonical commit.

**Exit criteria:** contract freshness, generated-client, controller, architecture,
format, and full backend tests pass.

## Phase 3 - Timeline Projection and Canonical References

**Goal:** Show one coherent history without copying ownership or leaking permissions.

- [ ] Write `ADR-087-journal-timeline-projection.md` if projector details extend
      ADR-086 materially.
- [ ] Define plain event payloads for Execution, Wellbeing, Feedback, Pantheon, and
      sparse Gamification milestones.
- [ ] Add durable idempotent projector workers with source-unique upserts.
- [ ] Enqueue projection work transactionally from each owning context where required.
- [ ] Project existing TrainingJournal writes in their local transaction or through
      the same durable mechanism chosen in ADR-086.
- [ ] Add source authorization resolvers through context public APIs; never import
      foreign schemas.
- [ ] Omit/redact inaccessible linked details while preserving the authorized parent.
- [ ] Add deep-link descriptors rather than frontend-generated route guesses.
- [ ] Add an idempotent backfill job for historical executions, injury reports,
      reviews, PRs, and meaningful milestones.
- [ ] Add dry-run counts, resumable cursors, telemetry, and mismatch reports.
- [ ] Test replay, out-of-order delivery, deleted/hidden sources, duplicate events,
      partial backfills, and privacy boundaries.

**Exit criteria:** a user's existing canonical history projects exactly once; source
details remain authoritative; retries converge.

## Phase 4 - Today Candidate Composition

**Goal:** Provide intelligent source-aware prefill without asserting completion.

- [ ] Write pure candidate-selection tests for active/completed executions,
      assignments, bookings with/without WOD, no candidate, and multiple candidates.
- [ ] Add public query functions returning plain candidate DTOs from Execution,
      Workouts, and Scheduling.
- [ ] Implement `MilosTraining.Application.GetTodayJournal` to compose candidates,
      today's actual entries, readiness, and capture capabilities.
- [ ] Deduplicate the same underlying source across assignment/booking/execution
      references without merging unrelated workouts.
- [ ] Return one explicit recommended presentation state, not an auto-selected actual.
- [ ] Write OpenAPI first, regenerate client, then add controller/router.
- [ ] Add ConnCase integration tests for independent, member, athlete, and admin users,
      timezone day boundaries, unpublished WODs, and unauthorized sources.
- [ ] Add a source-snapshot command that copies prescription data as plain values
      without mutating/importing Workouts schemas.

**Exit criteria:** Today payload explains every candidate and source; a booking alone
never creates permanent history.

## Phase 5 - Personal Workout Composer

**Goal:** Replace the need for the execution-only three-step logger when no execution
exists, while retaining Execution's canonical completion workflow.

- [ ] Build the composer against generated types and Journal API helpers.
- [ ] Start with title, occurrence, duration, RPE, add movement, and notes.
- [ ] Add progressive block/format controls only after basic logging works.
- [ ] Generate set/round/interval rows from count plus defaults.
- [ ] Implement `Apply to all`, `Copy previous`, add row, status, and row note.
- [ ] Render relevant metrics from measurement profile; support an explicit secondary
      metric action.
- [ ] Implement mobile expandable rows and desktop table layout with stable sizes.
- [ ] Prompt before removing populated rows and cover keyboard/screen-reader behavior.
- [ ] Show prescription quietly beside actual values for source-backed workouts.
- [ ] Support substitutions, omitted movements, extra movements, and extra work.
- [ ] Keep source snapshots immutable in client state.
- [ ] Add component tests for divergent later sets, round-linked movement rows,
      destructive count decrease, units, validation, and multiple workouts.
- [ ] Add visual/live checks at narrow mobile, tablet, and desktop widths including
      longest localized labels and RTL.

**Exit criteria:** an independent workout can be accurately recorded quickly, while a
user can still represent fatigue-driven changes set by set.

## Phase 6 - Today and Journal Frontend

**Goal:** Make the redesigned personal experience the first screen behind a feature
flag.

- [ ] Add `/journal` day/range/search route and a Today workspace at `/` for personal
      mode.
- [ ] Keep admin operational content accessible without denying admins their personal
      Journal.
- [ ] Render planned candidates separately from recorded history.
- [ ] Auto-open a single candidate only as an editable proposal; require a selector
      when multiple candidates exist.
- [ ] Always expose `Different workout` and post-save `Add workout` actions.
- [ ] Add compact Note, Body update, and Recovery composers.
- [ ] Render canonical timeline cards with source badges, sync state, visibility, and
      canonical deep links.
- [ ] Add date navigation, filtering, and text/entity search without introducing a
      duplicate storage model.
- [ ] Subscribe to user-scoped invalidations and refetch REST state.
- [ ] Update `TopNav` toward Today, Journal, Progress, Community/Coach, and conditional
      Gym destinations; preserve admin navigation.
- [ ] Add loading, empty, offline, stale, forbidden, and source-deleted states.
- [ ] Add component and Playwright tests for all candidate paths and multiple entries.

**Exit criteria:** feature-flag users can complete the core Today -> record -> Journal
workflow on mobile and desktop.

## Phase 7 - Offline Journal Commands and Conflict Resolution

**Goal:** Extend ADR-067 safely; do not put arbitrary commands into a generic replay
queue.

- [ ] Write `ADR-070-offline-journal-command-policy.md` before enabling adapters.
- [ ] Extract/reuse the versioned device-outbox envelope without coupling Journal to
      Messaging payloads.
- [ ] Add opt-in adapters only for server-idempotent Journal create commands first.
- [ ] Persist commands before network attempts and scope records by owner.
- [ ] Reconcile at authenticated bootstrap, `online`, and visibility return.
- [ ] Verify close, reload, sign-out/sign-in, and browser restart survival.
- [ ] Replace local pending records with canonical server records by operation UUID.
- [ ] Add versioned update commands only after a field-aware conflict payload and UX
      exist.
- [ ] Preserve both local and server versions during conflict review; never last-write
      wins silently.
- [ ] Add explicit retry/edit/remove controls for permanent failures, resolving the
      relevant Journal portion of TD-035.
- [ ] Test out-of-order retries, duplicate POSTs, token expiry, account switching,
      stale versions, deleted sources, and quota/storage failures.
- [ ] Run Playwright offline-close-reopen tests on desktop and mobile and assert one
      canonical server write.

**Exit criteria:** queued creates converge exactly once and stale edits require an
explicit resolution. Multi-device reads work after server acknowledgement.

## Phase 8 - Body Updates, Readiness, Recovery, and Notes Consolidation

**Goal:** Centralize capture while preserving specialized canonical ownership.

- [ ] Extend Wellbeing contracts/domain for side, numeric severity/pain, onset,
      activity context, training impact, status, visibility, and optional Journal
      target coordinates.
- [ ] Route Journal Body Update through an Application Service to Wellbeing, then
      project the canonical result into the timeline.
- [ ] Keep `/wellbeing` as Body & Recovery active-issues/trends read surface.
- [ ] Replace `WellbeingFormPanel` and the `/wellbeing` create form with deep links or
      the shared Journal composer; do not leave duplicate forms.
- [ ] Add readiness capture to Today while retaining Wellbeing trend ownership.
- [ ] Implement Journal-owned recovery and personal note commands.
- [ ] Migrate only truly personal standalone notes into Journal; preserve execution,
      movement/set, booking, message, feedback, and coach-private notes in place.
- [ ] Add source labels and redirects for legacy entry URLs.
- [ ] Use observational, non-diagnostic language in all locales.
- [ ] Test body-update-to-workout/movement/row links and independent authorization.

**Exit criteria:** one capture surface exists for each personal fact; active-issue and
trend views remain functional; no coach-private or contextual notes are reclassified.

## Phase 9 - Execution, Feedback, and PR Integration

**Goal:** Make existing canonical workflows feel unified without changing ownership.

- [ ] Reuse the composer's visual vocabulary in Execution finish/detail while keeping
      ADR-050 patches on the execution aggregate.
- [ ] Ensure completed executions create one timeline item and expose an edit/detail
      path, not a copied journal workout.
- [ ] Offer class/workout feedback contextually after a confirmed actual session;
      keep Feedback authoritative.
- [ ] Link PR facts to exact performance rows where provenance supports it.
- [ ] Add manual structured-workout PR detection only after validation and provenance
      rules are accepted.
- [ ] Keep manual workouts out of public leaderboard/challenge credit by default.
- [ ] Add an explicit link suggestion for similar manual log/later execution pairs;
      never auto-merge.
- [ ] Test prescription-versus-actual reconstruction, source deletion, feedback
      visibility, PR provenance, and duplicate prevention.

**Exit criteria:** users experience one coherent record while each source context
retains its invariants and audit history.

## Phase 10 - Sharing, Coaching, and Progress

**Goal:** Add collaborative value without weakening private-by-default semantics.

- [ ] Implement the Gate B relationship/authorization contract if not already present.
- [ ] Add per-entry `private` / `shared_with_coach` controls with explicit target and
      access preview.
- [ ] Show authorized shared entries in Coaching through public APIs/read projections.
- [ ] Allow coach-private notes to reference a Journal item without appearing in the
      user's payload.
- [ ] Verify that sharing a workout does not reveal linked private body/notes data.
- [ ] Build Progress reads for typed workload, consistency, RPE, performance-row,
      readiness, body-issue, and PR trends.
- [ ] Clearly label self-reported and app-verified facts in analytics.
- [ ] Add authorization matrix tests for owner, linked coach, unrelated admin, former
      coach, and other user.

**Exit criteria:** sharing is explicit and revocable; derived insights preserve source
quality and permissions.

## Phase 11 - Journal-First Navigation and Independent Onboarding

**Goal:** Complete the product repositioning after the underlying workflows are stable.

- [ ] Add onboarding that creates a useful private Journal without requiring gym or
      coach affiliation.
- [ ] Model gym/coach/community access as optional capabilities/relationships around
      the personal core; do not destructively rewrite historical role facts.
- [ ] Make Today the post-login personal destination and Journal the primary history.
- [ ] Keep Schedule, subscription/billing, and gym operations conditional on a gym
      relationship/entitlement.
- [ ] Preserve coach/admin operational destinations and fast switching to personal
      mode.
- [ ] Move WOD history and PR panels from the oversized landing page into Journal and
      Progress, preserving deep links and export/share actions.
- [ ] Update product copy to lead with durable training memory and accurate actuals;
      coach/gym connectivity is supporting value.
- [ ] Test independent, member, athlete, coach/admin, linked, unlinked, expired
      membership, and relationship-removal journeys.

**Exit criteria:** an unlinked user reaches useful capture immediately; linked users
retain logistics and coaching workflows without a parallel logging model.

## Phase 12 - Migration, Rollout, and Hardening

**Goal:** Roll out without lost history, broken links, or privacy regressions.

- [ ] Run timeline backfill dry-runs and compare source/projected counts by context.
- [ ] Add observability for projection lag/failures, outbox age, conflict frequency,
      duplicate prevention, capture completion, and legacy-route use.
- [ ] Add repair/replay tooling that is idempotent and owner-scoped.
- [ ] Verify data export includes canonical Journal records and authorized references.
- [ ] Run complete backend/frontend/unit/integration/contract/architecture/i18n suites.
- [ ] Run Playwright journeys on desktop/mobile for independent and linked users,
      offline create, multi-device read, privacy, and legacy redirects.
- [ ] Verify screen reader, keyboard, reduced motion, RTL, long localization, and
      browser storage failure behavior.
- [ ] Roll out internal -> selected users -> all users behind reversible flags.
- [ ] Remove old capture UI only after telemetry shows successful replacement and all
      deep links have redirects.
- [ ] Update ADR implementation notes, resolve TD-033, update the applicable part of
      TD-013/TD-035, and record any remaining debt.
- [ ] Update the base design document and historical plan maintenance note after
      general availability.

**Exit criteria:** migration reports reconcile, rollback is tested, no duplicate input
surface remains, and all live-test evidence is recorded.

## Required End-to-End Acceptance Scenarios

1. An independent user logs a five-set workout, changes reps/load in sets four and
   five, closes offline, signs in later, and receives one canonical record.
2. A linked athlete selects one of multiple assignment/class candidates, copies the
   prescription into actual rows, records divergent performance, and leaves the
   prescription unchanged.
3. A booked class with no published WOD prefills only class metadata and creates no
   history until explicit save.
4. A completed execution appears once, opens its execution-owned actual patches, and
   is not duplicated as an independent workout.
5. A user logs two workouts, a note, and a body update on one date; each retains its
   own ID/time and correct links.
6. A body update links to a workout movement/set; sharing the workout does not expose
   the private body update.
7. Two devices edit the same journal workout; the stale offline device receives a
   conflict and cannot silently overwrite the newer server version.
8. Existing injury, review, PR, execution, and coach-note records survive backfill;
   only authorized facts appear in the user's Journal.
9. An unrelated admin cannot read a `shared_with_coach` entry without the explicit
   relationship required by Gate B.
10. Legacy wellbeing/history links resolve to the new canonical read or redirect and
    do not expose a second create form.

## Recommended Commit Sequence

1. `docs(journal): accept context ownership - keep canonical domains intact`
2. `feat(journal): add aggregate schema - preserve independent workout actuals`
3. `feat(journal): add domain and persistence - enforce row-level truth`
4. `feat(journal): publish API contracts - make sync and conflicts explicit`
5. `feat(journal): project canonical history - avoid duplicated source records`
6. `feat(journal): compose Today candidates - prefill without asserting completion`
7. `feat(web): add personal workout composer - capture divergent sets quickly`
8. `feat(web): add Today and Journal - unify capture and history`
9. `feat(journal): add offline reconciliation - converge creates exactly once`
10. `refactor(wellbeing): centralize body capture - retain active-issue views`
11. `feat(journal): integrate execution feedback and PR references`
12. `feat(coaching): share selected journal entries - preserve private boundaries`
13. `refactor(web): adopt journal-first navigation - support independent users`
14. `chore(journal): backfill and roll out - preserve existing history`
