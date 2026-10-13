# ADR-130: Injury Warnings on the Ready Screen, Scaled Variations and Drop-off Facts
Date: 2026-10-13
Status: Accepted

## Context
TD-088 is the follow-up to ADR-124 (injury-aware workout safety warnings).
ADR-124 deferred these items:

- The athlete's own warning on the execution ready screen. The timer
  rewrite was still on another branch.
- Warnings while a coach edits a workout.
- Variation-aware matching. Only the Rx exercise of a scaled variation was
  evaluated.
- Injury facts on abandoned executions and on training-log entries.
- Admin analytics tiles by injury segment.
- Body-area recognition beyond English and Greek, or a structured
  body-area picker.

The timer work has now merged. `ExecutionMode` shows `ReadyScreen` for a
fresh execution, and the execution store knows `workoutId` and
`scaleSlug`. The self surface enum already contained `pre_start`, but
nothing rendered it.

The ADR-124 constraints still apply:

- Warnings inform and never block.
- A personal injury never becomes a tenant analytics fact (ADR-055).
- Analytics metadata holds only enums, counts, ids and booleans.
- Every read runs inside a `RepoContext` session.

## Decision
1. **Ready screen.** `ReadyScreen` gets an informational `notice` slot
   above the plan. `ExecutionMode` fills it with `MyInjuryWarningsPanel`
   when the execution has a workout, passing:
   - `surface: "pre_start"`;
   - `sourceContextId`: the execution id;
   - `scale`: the execution's scale level.

   The panel keeps its acknowledge button and its analytics. Start stays
   enabled and nothing waits on the request. The surface value was already
   allowed, so the enum is unchanged.
2. **Scale-aware matching.**
   - `ExerciseDescriptors` skips exercises that the materialized scale
     excludes.
   - When an applied variation overrides the exercise name, the exercise
     is resolved by that name and not by the base catalog ref. The
     override is a different movement.
   - `Workouts.exercise_descriptors/2` materializes the workout for a scale
     slug first. A blank scale means Rx.
   - Contract-first, the self endpoints accept an optional `scale`, in the
     query or the acknowledge body. Its shape is the `ScaleLevel.slug`
     pattern, max 64 characters; anything else is a 422. Responses echo
     `scale_level_slug`.
   - The application layer treats a malformed scale as Rx, so a direct
     call never fails because of it.
   - Completion facts were already computed from the scale-materialized
     workout, so they become scale-aware without further change.
3. **Per-execution ready-screen events.** For `pre_start` events whose
   source context is an execution id, the dedupe key includes that id.
   They are recorded once per execution instead of once per day, so they
   can be joined to the execution later. The injury-warning metadata
   allowlist also gains `scale_level_slug`.
4. **Drop-off facts.**
   - `workout_execution_abandoned` gains `had_active_injury`,
     `injury_warning_level`, `injury_warning_shown` and
     `injury_warning_acknowledged`. The last two say whether the ready
     screen recorded those events for that execution.
   - `training_log_entry_logged` gains `had_active_injury` and
     `injury_warning_level`. They are computed against the logged workout
     at the logged scale.
   - All of these facts come from organization-provenance injuries only.
   - The abandonment sweep reads every pending execution's ready-screen
     events in one tenant-scoped query through the new
     `Analytics.list_events_for_source_contexts/2`.
5. **Body-area synonyms for every UI locale.**
   - `InjuryRiskPolicy` merges a per-region `@locale_synonyms` table into
     its regions at compile time. It covers es, fr, de, it, pt, nl, ru, bg,
     ar and he.
   - Synonyms are written naturally and normalized exactly like the input.
   - A trailing space marks a whole-word synonym, for short or ambiguous
     words.
   - Arabic and Hebrew list both the bare form and the definite-article
     form.

## Rationale
- **The ready screen is the last moment before load.** A `notice` slot
  keeps `ReadyScreen` free of data fetching and query wiring, so it stays a
  pure presentational component. `ExecutionMode` already owns the session
  and store values the panel needs.
- **Evaluate what the athlete will actually do.** Rx-only matching both
  over-warns (an excluded or substituted movement still warns) and
  under-warns (a substitute that loads the injured area is ignored).
  Materializing first reuses the single scale rule (`WorkoutMaterializer`).
- **Join through the analytics store.** The dedupe change and the
  source-context lookup let the sweep answer "was this athlete warned
  before abandoning?" from data that already exists. It needs no new
  column, migration or table. These events are only recorded from
  organization-provenance evaluations, so the booleans cannot reveal a
  personal injury.
- **Synonyms in code, not a picker.** This follows ADR-124's choice of a
  reviewable code-owned table. The table is now complete for every locale
  the UI ships.

## Alternatives Considered
- **Putting the panel inside `ReadyScreen` itself.** Rejected. It would
  couple a presentational component to TanStack Query and to the session.
- **A blocking confirm step before Start.** Rejected, as in ADR-124.
- **Storing injury flags on `workout_executions` or `training_log_entries`
  rows.** Rejected. It would copy health-adjacent facts into operational
  tables that more roles can read. It would also need a migration, and
  analytics events already carry segmentation facts.
- **Including the source context in every surface's dedupe key.**
  Rejected. Class roster and assignment surfaces are meant to count once
  per day. Only the execution-scoped ready screen needs per-execution rows.
- **A structured body-area picker.** Deferred. It changes the injury
  report forms and their data shape. The synonym table removes most
  free-text misses first.

## Consequences
- Athletes see their own warnings, including personal injuries, at the
  moment they start a workout, evaluated for their scale. Staff analytics
  can now segment abandonment and training-log entries by injury status,
  and by whether the warning was seen or acknowledged.
- Each ready-screen view of a new execution records one
  `injury_warning_shown` row, when the tenant's injuries warn. Previously
  it was one per day.
- The abandonment sweep does one extra analytics query per run. It also
  does one Wellbeing read per pending execution, capped by the sweep's
  batch of 500.
- The synonym table is opinionated and prefix-based. Unrecognised areas
  still produce the ADR-124 caution.

## Implementation Notes
Implemented on 2026-10-13 (TD-088).

- **Tests.**
  - Domain (pure): `ExerciseDescriptors` has 2 new tests (scaled
    materialization, and an override-less variation). `InjuryRiskPolicy`
    has 2 new tests (49 body areas across 10 locales, and the whole-word
    guard). `EventCatalog` has 2 new tests.
  - Application: `injury_warnings_test.exs` has 5 new tests, run
    `@moduletag :rls_enforced`. They cover Rx versus scaled evaluation,
    scale-aware completion facts, abandoned executions joined to
    ready-screen shown/acknowledged events, personal-only injuries never
    reaching abandonment facts, and training-log facts.
  - ConnCase: 1 new test covers the `scale` parameter, per-execution
    `pre_start` analytics, the acknowledge body and the 422 for a malformed
    scale.
  - Vitest: 2 request-helper tests, 1 panel test, and 2 `ExecutionMode`
    tests. One shows that the ready screen renders the panel with the right
    props and that Start stays enabled. The other shows no panel for an
    execution without a workout.
- **Contract.** `openapi.json` and `schema.ts` were regenerated. The diff
  only adds `scale` and `scale_level_slug`.
- **No migration, no new dependency, no new UI copy.** The ready screen
  reuses the existing self-warning messages.
- **Free-text execution** (`FreeTextExecutionMode`) has no ready screen,
  so it shows no pre-start panel. Its workouts still get completion facts
  through `CompleteWorkout`.
- **Deferred.**
  - Warnings in the workout editor. The editor works on unsaved drafts,
    and ADR-124 evaluation is defined on published workouts through
    `Workouts.get_workout/1`. Assignees are chosen afterwards, in the
    assign dialog or quick-assign, and those already show staff warnings.
    The real gap is the ADR-125 substitute flow (`substitute_for_assignment`,
    `substitute_for_slot`). There a coach publishes a variant for known
    members without passing through the assign dialog. Closing it needs
    staff evaluation of a draft, or of unsaved exercise descriptors, for
    those assignees.
  - Admin analytics tiles by injury segment. The facts are now recorded on
    completion, abandonment and training-log events, but showing them
    needs new admin dashboard queries and UI.
  - A structured body-area picker in the injury report forms.
  - Staff-side scale awareness. The assign dialog and class roster still
    evaluate Rx, because no scale is chosen at that point.
