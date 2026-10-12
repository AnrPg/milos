# ADR-114: Injury-Aware Workout Safety Warnings
Date: 2026-10-12
Status: Accepted

## Context
TD-013: the Wellbeing context stores injury reports (`body_area`,
`severity`, `status`, `training_limitations`, `tags`, `visibility`,
`organization_id` provenance) with a status history, plus admin and member
pages. Nothing used that data where training decisions are made. A coach
could assign a squat-heavy workout to an athlete with an active knee injury
and see nothing. An athlete could open the same workout and get no reminder.
Analytics also could not segment executions by injury status.

Constraints:

- ADR-055 / F-28: a self-reported injury is personal and owned by the
  member. It has no `organization_id` and follows the member across gyms.
  Staff may only see injuries with their organization's provenance,
  including `admin_only` notes. The member never sees `admin_only` notes.
- ADR-091 / ADR-109: every tenant read runs inside a `RepoContext` session
  under forced RLS. The `injury_reports` policy is owner-OR-tenant, so a
  staff session can still see the staff member's own rows. The tenant
  predicate must therefore be explicit.
- ADR-113: analytics events go through the `EventCatalog` allowlist. Their
  metadata holds only ids, enums, counts and booleans, with no free text.
- The timer UI (ExecutionMode, TimerDisplay, timer engine, score modal) is
  being rewritten on another branch and must not be restructured.
- Warnings must inform and never block an action.

## Decision
1. **A pure domain policy.** `Wellbeing.Domain.InjuryRiskPolicy` maps active
   injuries and exercise descriptors (`name`, `exercise_ref`, `category`) to
   warnings. It works in three steps:
   - **Exercise to movement patterns.** It uses a curated table keyed by the
     stable Quick Text catalog ids (`Workouts.Domain.WorkoutDsl.ExerciseCatalog`).
     Name heuristics are the fallback for free-text exercises.
   - **Injury to body regions.** It resolves the free-text `body_area` to
     canonical regions: shoulder, elbow, wrist, neck, back, hip, knee,
     hamstring, ankle, chest and core. Matching is accent-insensitive
     word-prefix matching, with English and Greek synonyms. Tags that name a
     body area add that region.
   - **Region and severity to a level.** Each region lists the movement
     patterns that load it directly (primary) or indirectly (secondary).
     Severity scales the result:

     | Severity | Primary | Secondary |
     |---|---|---|
     | mild | caution | none |
     | moderate | avoid | caution |
     | severe | avoid | avoid |

   Two rules adjust the level:
   - Restriction tags (`no-overhead`, `impact`, `no-running`, …) always set
     the restricted patterns to `avoid`.
   - Mobility work is capped at `caution`.

   An active injury whose body area is not recognised still produces one
   `caution` warning with no exercises.
2. **Visibility lives in one application helper.** `Application.InjuryWarningEvaluation`
   defines who sees what:
   - **Staff** call `Wellbeing.list_active_injuries_for_users/1`. It uses
     the tenant predicate only, so staff see organization-provenance
     injuries, including `admin_only` ones. They never see a personal
     report or another tenant's report.
   - **The athlete or member** calls `Wellbeing.list_active_injuries_for_user/1`.
     It returns their own injuries that are visible to them: personal and
     every gym's `user_and_admin` reports.

   Every read runs inside `Wellbeing.with_tenant_context/2`. The workout is
   resolved through `Workouts.get_workout/1`, which returns published
   workouts only, inside the same session. `Workouts.exercise_descriptors/1`
   reduces the workout to descriptors without leaking Workouts internals.
3. **Use cases and endpoints (contract-first).** All endpoints are
   informational only.

   | Use case | Endpoint | Audience |
   |---|---|---|
   | `EvaluateAthleteInjuryWarnings` | `POST /api/org/:slug/admin/wellbeing/injury-warnings` | Staff, from the assign dialog or member dossier |
   | `AcknowledgeAthleteInjuryWarnings` | `POST …/admin/wellbeing/injury-warnings/acknowledge` | Staff |
   | `ListClassSlotInjuryWarnings` | `GET …/admin/schedule/slots/:id/injury-warnings` | Staff; covers pending and approved bookings |
   | `GetMyWorkoutInjuryWarnings` | `GET /api/org/:slug/me/workouts/:workout_id/injury-warnings` | Every tenant role |
   | `AcknowledgeMyInjuryWarnings` | `POST …/me/workouts/:workout_id/injury-warnings/acknowledge` | Every tenant role |

4. **Analytics segmentation without health leakage.**
   - Two new events, `injury_warning_shown` and
     `injury_warning_acknowledged`, have context type `workout`, use
     explicit dedupe and carry a per-event metadata allowlist in
     `EventCatalog`. The allowed keys are `audience`, `surface`,
     `warning_level`, `injury_warning_count`, `avoid_exercise_count`,
     `caution_exercise_count`, `athlete_id` and `source_context_id`.
   - `workout_execution_completed` gains `had_active_injury` (boolean) and
     `injury_warning_level` (`none`, `caution` or `avoid`).
   - All analytics facts come from the acting tenant's organization-provenance
     injuries only. A personal injury never becomes a tenant analytics fact,
     not even as a boolean.
5. **UI.** Self-contained components in
   `apps/web/src/components/wellbeing/InjuryWarnings.tsx` are rendered from
   stable entry points:
   - the assign-workout page and the quick-assign modal, re-evaluated when
     the selection changes;
   - the admin class slot view, with badges next to booked members plus a
     details panel;
   - the athlete assignment detail panel and a member's booked class detail.

   The components disable nothing, and a failed load shows a quiet notice.

## Rationale
- **A code-owned table keyed by catalog ids** is deterministic, reviewable
  and testable. A coverage test fails whenever the catalog grows without a
  mapping decision. The ids are stable by contract, while labels and aliases
  may change. Name heuristics cover structured and free-text workouts that
  carry no ref. `ExerciseDescriptors` also resolves canonical and alias
  names to refs first.
- **Movement patterns as the middle layer** keep the region table small. One
  pattern change, such as adding `:wrist_extension` to front-rack movements,
  fixes every region at once.
- **Server-side evaluation** keeps the visibility rules in one place, next to
  RLS. Acknowledgements are re-evaluated on the server, so the client never
  supplies levels or counts to analytics.
- **Analytics from organization provenance only.** Staff analytics are
  tenant-readable. A personal injury reaching them would breach ADR-055
  data ownership. The trade-off is that an athlete's own warnings that come
  only from personal injuries are invisible to tenant analytics, by design.

## Alternatives Considered
- **Free-text matching of `training_limitations` against exercise names.**
  Rejected. It is noisy, language-dependent, and would push free text into
  matching logic that staff cannot audit. The limitation text is shown
  verbatim instead.
- **A DB table for the body-area mapping.** Rejected for the MVP. It would
  need a migration, an admin UI and RLS for what is clinical-ish curated
  content. A code-owned table can move to configuration later.
- **Blocking or confirm dialogs on assign or start.** Rejected. The
  decision is explicitly informational. Coaches know context the system
  does not.
- **Client-side evaluation from the injury list.** Rejected. Staff would
  have to download injury lists they do not otherwise need, and the
  visibility rules would be duplicated in TypeScript.
- **Recording analytics from the athlete's full injury set.** Rejected
  because personal health data would leak into tenant analytics (ADR-055).
- **Putting the warning inside ExecutionMode or the ready screen.**
  Deferred. Those files are being rewritten on the timer branch.

## Consequences
- Staff and athletes see consistent, explainable warnings: level,
  triggering exercises, body area, severity and limitation text.
- `injury_warning_shown` is recorded once per actor, subject athlete,
  workout, surface and UTC day. Re-renders and refetches do not inflate it.
- The mapping is opinionated. Physiotherapy-grade accuracy is out of scope,
  and the UI copy says warnings are informational.
- Body-area recognition covers English and Greek synonyms. Other languages
  fall back to the unrecognised-area caution.
- Follow-up work is listed in Implementation Notes.

## Implementation Notes
Implemented on 2026-10-12 (TD-013).

- **Domain.** `Wellbeing.Domain.InjuryRiskPolicy` exposes `evaluate/2`,
  `exercise_patterns/1`, `regions_for/1`, `max_level/1`,
  `analytics_facts/1` and `catalog_patterns/0`. Its unit tests include the
  catalog coverage test, which reads `ExerciseCatalog.entries/0` from the
  test only, so there is no compile-time dependency. `foam-roll` is the one
  explicit "no relevant loading" entry. Workouts gained the pure
  `Workouts.Domain.ExerciseDescriptors` and the public
  `Workouts.exercise_descriptors/1`.
- **Store.** `EctoWellbeingStore.list_active_tenant_injuries_for_users/1`
  uses `scoped_to_tenant/1`, not the owner-or-tenant disjunction, so a staff
  session never returns the staff member's own rows. The query caps the
  user set at 250.
- **Application.** `InjuryWarningEvaluation` is the shared helper. The use
  cases are `EvaluateAthleteInjuryWarnings`, `AcknowledgeAthleteInjuryWarnings`,
  `ListClassSlotInjuryWarnings`, `GetMyWorkoutInjuryWarnings` and
  `AcknowledgeMyInjuryWarnings`. To feed the completion facts,
  `CompleteWorkout` now threads the resolved workout out of
  `timer_sequence_for_execution`, and `completion_facts/2` is best effort
  (`%{}` on any failure). Staff surfaces are `assign_dialog`,
  `class_roster` and `member_dossier`. Self surfaces are
  `assignment_detail`, `class_detail` and `pre_start`. Unknown surfaces are
  rejected by the OpenAPI enum with a 422, and dropped by the service if
  called directly.
- **Tests.**
  - Domain: 16 tests. ExerciseDescriptors: 2. EventCatalog: 3 new.
  - Application: 12, in `injury_warnings_test.exs`, run
    `@moduletag :rls_enforced`. They cover two tenants, admin-only versus
    user-visible reports, personal reports, the roster path, analytics
    allowlisting, completion facts and an end-to-end
    `workout_execution_completed`.
  - ConnCase: 6, covering staff, roster, self, a 403 for the athlete role, a
    404 across tenants and 422s for validation.
  - Vitest: client scoping, helpers and components.
- **Web.** `/me/workouts` was added to the tenant-scoped prefixes in
  `src/api/client.ts`. The generated client was regenerated. The textual
  diff of `openapi.json` is large because of the exporter's map ordering;
  semantically it adds only the 5 paths and 7 schemas.
- **Deviation.** The brief mentioned the member dossier. The staff use case
  supports `member_dossier` as a surface, but no dossier UI was added. The
  dossier has no workout context, so a per-workout warning has nothing to
  evaluate there.
- **Environment note.** Large `mix test` runs on the shared agent machine
  can exhaust the BEAM literal area (`literal_alloc`). Gates were run with
  `ELIXIR_ERL_OPTIONS="+fnu +MIscs 4096"`. This is not a code issue.
- **Deferred follow-up.**
  - Render `MyInjuryWarningsPanel` (surface `pre_start`) on the timer
    branch's ready screen once it lands. Do not edit ExecutionMode before
    then.
  - Show warnings while editing a workout in the admin workout editor, for
    example the athletes it is assigned to.
  - Admin analytics tiles that segment completion and abandonment rates by
    `had_active_injury` and `injury_warning_level`.
  - Add `had_active_injury` to `workout_execution_abandoned` and to
    training-log entries.
  - Consider variation-aware matching. Today only the base exercise of a
    scaled variation is evaluated.
  - Extend body-area synonyms beyond English and Greek, or add a structured
    body-area picker to the injury forms. A picker would remove free-text
    ambiguity.
