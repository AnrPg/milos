# ADR-118: Standalone Training-Log Entries
Date: 2026-10-12
Status: Accepted

## Context
ADR-050 deliberately kept actual-workout facts on the timer-backed
`workout_executions` aggregate and deferred a separate log (TD-033). That left a
real gap: members who attend a class without starting the timer, athletes who do
an assigned workout offline, and anyone training away from the gym had no way to
record the session, so streaks, totals, and challenges under-counted real
training.

Overloading `workout_executions` for this would mean fabricating timer state
(`started_at_utc`, segment indices, elapsed counters, lock versions for
progress operations) for sessions that never had a timer, and would blur the
source authorization rules from ADR-029 (an execution start must bind to a
proven relationship at the moment it starts). Non-execution logs also need
their own lifecycle (edit, void) that executions do not have.

## Decision
Introduce a standalone `training_log_entries` aggregate owned by the
**Execution** context, next to (not inside) `workout_executions`.

- **Ownership and tenancy.** Tenant-owned rows (`organization_id` NOT NULL,
  `user_id` NOT NULL) with forced RLS. The policy mirrors the owner-or-tenant
  sibling tables: `USING (user_id = app.user_id OR organization_id =
  app.organization_id)` and `WITH CHECK (user_id = app.user_id AND
  organization_id = app.organization_id)`. The Ecto adapter additionally stamps
  `organization_id`/`user_id` from the session GUCs and restricts reads to the
  acting owner, so another member (or the tenant owner) never sees an entry.
  Routes live under `/api/org/:organization_slug/me/training-log` behind
  `ResolveTenantContext` (ADR-091); every application service fails closed with
  `:organization_context_required`.
- **Source selection.** `source_type` is one of:
  - `class` - a scheduled class (`source_reference_id` = slot id) that has
    started and for which the member has an `attended` mark or an approved
    booking; an explicit non-attendance mark (`missed`, `no_show`, ...) always
    wins. Resolved through the Scheduling public API.
  - `assigned_workout` - an assignment linked to the athlete and not rejected
    (Workouts public API).
  - `library_workout` - a published workout of the tenant, for the roles that
    may self-select (owner/admin/coach/member), mirroring ADR-029.
  - `freeform` - no reference; the user supplies the title.
  Workout, booking, title, and workout type are derived server-side; only the
  source type and reference id come from the client.
- **Payload.** Performed time + timezone, duration, perceived effort (1-10),
  notes, `section_scores` (only for scoreable sections of the source workout),
  ADR-050 `exercise_modifications` patches (only when the source has a
  canonical workout; validated by the same `ModificationPatchValidator`), and
  `performed_exercises` rows (name, optional catalog `exercise_ref`, sets, reps,
  load + unit, distance + unit, duration, calories, note) for work without a
  canonical prescription.
- **Invariants.**
  - No double counting: a class/assignment already counted by a *completed*
    execution of the same booking/assignment cannot be logged; a library workout
    conflicts only with a completed execution of the same workout on the same
    calendar day (library workouts are repeatable).
  - One live log per class / assignment per user (partial unique index on
    `status = 'logged'`); voiding frees the slot for a corrected entry.
  - Idempotency: a client `idempotency_key` (unique per tenant + user) makes a
    retried submission return the original entry (`200`) instead of a
    duplicate (`201`).
  - Owner edits of performed details with optional `expected_version`
    optimistic locking; source fields are immutable.
  - Entries are never deleted: they are voided (`status`, `voided_at`,
    `void_reason`). Voided entries are frozen.
- **Completion and gamification.** Logging enqueues the existing
  `ProcessWorkoutCompletionJob` in the same transaction as the insert (ADR-029
  durable handoff) with `source: "training_log"` and the entry/tenant/user ids.
  The job projects the entry into the execution-shaped completion record that
  `Gamification.record_workout_completion/1` already consumes, and
  `CompleteWorkout.process_completion/1` now merges live training-log
  completions (across the user's tenants, like executions) into its completed
  list. Streaks, totals, milestone/type badges, perseverance, and seasonal
  challenges therefore count logged workouts on their performed date.
- **PR detection** applies to sourced entries whose `section_scores` target
  scoreable sections of the source workout (same `PRDetector` path as
  executions). Freeform entries never auto-detect PRs in this slice, even when
  `performed_exercises` carry an `exercise_ref`; the reference is persisted so a
  later projection can map it to Pantheon PRs.
- **Voiding** does not crash projections (a job for a voided entry cancels with
  `:training_log_entry_voided`) and removes the entry from every subsequent
  projection run, but does not retroactively reverse streaks, badges, PR
  events, or challenge progress already awarded.

## Rationale
A sibling aggregate keeps timer execution state honest while reusing every
piece that already works: the ADR-050 patch shape and validator, the ADR-029
Oban handoff, and the gamification projection. Placing it in the Execution
context keeps "a workout was performed" facts in one bounded context and lets
the completion projection read both sources through one public API.

Projecting entries into the execution completion shape avoids a parallel
gamification path; the projection already rebuilds streaks and totals from the
full completed list on each run, which is also what makes a void stop counting
without bespoke reversal code.

## Alternatives Considered
- **Synthetic `workout_executions` rows** (status `completed` with fake timer
  fields): rejected - it corrupts timer/progress invariants, reuses ADR-029
  start-time authorization for a different moment, and cannot express voiding.
- **A new bounded context ("Journal")**: rejected for now - it would need its
  own cross-context read of executions for the double-count check and a second
  completion pathway, with no ownership benefit.
- **Hard delete instead of void**: rejected - logs feed audit-style history and
  projections; deletion would silently desynchronize awarded gamification.
- **Retroactive recomputation on void**: deferred - streak/badge/challenge
  reversal needs a full replay of the user's projection state (see
  Consequences).

## Consequences
- The completion projection now reads two sources; any new consumer of
  "completed workouts" must use `CompleteWorkout.process_completion/1` inputs or
  `Execution.list_training_log_completions_for_user/1`, not
  `workout_executions` alone.
- `ProcessWorkoutCompletionJob` uniqueness keys are now
  `[:execution_id, :training_log_entry_id]`.
- Known gaps recorded as follow-up debt:
  - Voids and edits do not retroactively recompute streaks, badges, PR events,
    or challenge progress; they only affect future projection runs.
  - The weekly leaderboard materialized view and coaching/analytics aggregates
    still count `workout_executions` only; including logs needs an additive
    view rebuild.
  - The athlete "my workouts" week view still derives assignment completion
    from executions only, so a logged assignment is not shown as completed
    there (it is filtered out of the log source picker).
  - No automatic PR detection for freeform `exercise_ref` rows.
  - Coaches cannot yet read members' training-log entries in the athlete
    dossier / drill-down.

## Implementation Notes
Implemented on 2026-10-12 (TD-033).

- Migration `20261012100000_create_training_log_entries` is additive: new
  table, check constraints (source types, status, freeform-has-no-reference,
  effort 1-10, non-negative duration), the idempotency unique index, the partial
  "live source" unique index, and the forced RLS policy. The table is registered
  as a ready tenant table in `MilosTraining.Infrastructure.Tenancy.Audit` and
  `execution/training_log_store` joined the `mix milos.architecture` tenant
  store list.
- Layering: `Execution.Domain.TrainingLogPolicy` holds all rules (detail
  normalization, class authorization decision, double counting, source-picker
  filtering, scoreable sections, completion projection) as pure functions with
  `now` injected. Commands `LogTrainingEntry`, `UpdateTrainingLogEntry`,
  `VoidTrainingLogEntry`; query `GetTrainingLogEntries`; port
  `Execution.Ports.TrainingLogStore`; adapter
  `Infrastructure.Execution.EctoTrainingLogStore`. Application services
  `AuthorizeTrainingLogSource`, `LogTrainingEntry`, `UpdateTrainingLogEntry`,
  `VoidTrainingLogEntry`, `ListTrainingLogEntries`, `ListTrainingLogSources`.
- The class source references the scheduled class (slot) rather than the
  booking, because walk-ins can carry an attendance mark without a booking; the
  derived booking id is stored to run the double-count check against
  class-booking executions.
- The source picker looks back 30 days for classes and assignments and lists up
  to 100 published library workouts; scoreable sections are offered for class
  and assignment sources only (the library list stays light), although the API
  accepts library `section_scores` for scoreable sections.
- Logging does not pass through finance entitlement authorization: it grants no
  access to content (class access was entitled at booking time; library
  workouts are already visible to the member).
- Editing does not re-run the completion projection; gamification is computed
  once, at log time, mirroring executions being immutable after completion.
- Frontend: `TrainingLogSection` on the member/athlete home (next to workout
  history) lists entries, opens a mobile bottom-sheet dialog with a source
  picker (class / assigned / library / freeform) and form, and supports edit and
  void. All copy is in the `Ui` catalogs for all 12 locales; new API error codes
  map to localized messages. Pure payload/validation logic lives in
  `src/lib/training-log.ts` with vitest coverage plus a component test.
- Verification: domain unit tests, DB integration tests for the application
  services (including two-tenant and peer isolation, idempotent replay, double
  counting, void/re-log, optimistic locking, and gamification counting), an RLS
  test on a non-superuser connection, Oban job tests for the training-log
  branch, and ConnCase controller tests. A full browser live test was not run in
  this session; behavior was verified through the API-level ConnCase flows.
