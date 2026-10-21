# ADR-163: WOD goals, «τι ένιωσες» feedback and the anatomy taxonomy
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.6 and Phase 3 milestone P3-M1 ask for goals on a workout: the muscles it
targets (primary, secondary, stabilizer), the fitness qualities it develops (the ten
general physical skills) and a stimulus line. The coach gets an automatic suggestion
from the exercises and a toggle «Εμφάνιση στόχων στα μέλη». After the workout the
athlete ticks what they *felt*; that feeds muscle coverage and the qualities radar
(P3-M3) and the anatomy atlas (ADR-164, P3-M2).

Three things had to be settled: where the muscle vocabulary lives and how it lines up
with the atlas meshes and the exercise vocabulary; how a suggestion is computed so it
is explainable and testable; and how goals and feedback are stored and protected,
given that feedback is written on two different journal item kinds (executions and
training-log entries) whose rows live under different scopes.

The vision asks to reuse existing data rather than invent a parallel taxonomy. The
repo has two exercise vocabularies: the analytics `exercise_catalog_entries` (free
`muscle_groups` strings) and the Quick Text catalog (`ExerciseCatalog`, stable slugs,
already the key of the injury-risk policy, ADR-124). Neither has a muscle tree.

## Decision
1. **Code-owned, versioned taxonomy.** `Anatomy.Domain.MuscleTaxonomy` holds a
   region → group → head tree with stable slug ids. Every group and head carries the
   Terminologia Anatomica 2 ids of the atlas meshes that draw it (anatomy-models
   `ta2-<id>.<side>` nodes, ADR-164), so API, atlas and coverage share one vocabulary.
   `version/0` is bumped whenever nodes are added or removed. `FitnessQualities`
   holds the ten qualities. No reference tables.
2. **Exercise targets keyed by Quick Text catalog ids.** `Anatomy.Domain.ExerciseTargets`
   maps each catalog id to muscles with roles and to qualities, keyed exactly like the
   injury-risk policy, with a test that fails when the catalog gains an id without an
   entry.
3. **Deterministic suggestion.** `GoalSuggestion.suggest/1` takes the workout's
   exercises with a weight (set count when known, else 1): strongest role per muscle,
   stabilizers kept only above a share of the workout and capped, a head dropped when
   its group already says it, qualities ranked by weight. The result reports how many
   exercises were recognised and how many were not. An AI layer may refine it later
   but is never required. Exercises come from the workout's sections (structured and
   Quick Text; a draft's from its draft data) or, for a free-text workout without
   sections, from its body read line by line against the catalog (longest match,
   plural-tolerant).
4. **`workout_goals` table** (Workouts context, `Workouts.GoalStore` port and facade):
   one row per master workout (unique, cascade on delete), `muscles` jsonb
   `[{id, role}]`, `qualities` text[], `stimulus`, `visible_to_members` (default
   false), `source` `suggested|edited`, `taxonomy_version`, `updated_by_id`. Tenant
   content under the bare tenant policy, exactly like `master_workouts`; which members
   see a row is decided by the use case (`visible_to_members`). Duplicating a workout
   copies its goals in the same transaction.
5. **`goal_feedback` table** (Journal context, `Journal.GoalFeedbackStore`): one row
   per `(entry_kind, entry_id, user_id)` with `entry_kind` `execution|training_log`,
   `felt_muscles`, `felt_qualities`. It is the member's own data and follows its entry
   like a journal comment (ADR-140): owner-only writes, and only on an entry the
   writer owns (`palee_journal_entry_owner`); coaches read it only while the entry's
   rung reaches them (`palee_entry_visible_to_acting_coach`, and the ADR-162 shared
   read). A SECURITY DEFINER `palee_goal_feedback_entry(kind, id)` returns an entry's
   owner, gym, workout and voided flag for the use case.
6. **Static taxonomy endpoint** `GET /api/anatomy/taxonomy` (authenticated): version,
   nodes in tree order (`id, kind, parent_id, name, ta2_ids`), qualities and roles,
   with a content ETag and `Cache-Control: private, max-age=86400`; a matching
   `If-None-Match` gets 304. Display names are translated on the client
   (`anatomy.<id>`, `anatomy.quality.<id>`).

Endpoints: `GET/PUT /api/org/:slug/admin/workouts/:id/goals` (capability
`manage_workouts`), `GET /api/org/:slug/workouts/:id/goals` (any member of the gym,
athletes included), `GET/PUT /api/org/:slug/me/goal-feedback/:entry_kind/:entry_id`
(the entry's owner).

## Rationale
- A code-owned tree versioned with the code is reviewable in a diff, needs no seeding
  per environment, and can carry the atlas mesh ids the 3D asset needs. Keying targets
  by the Quick Text ids reuses the vocabulary the injury-risk policy already curates,
  which honours "don't invent a parallel taxonomy" for exercises.
- A deterministic suggestion is explainable to a coach, stable under test and free;
  the coach always edits before anything reaches members (members never see an unsaved
  suggestion).
- One feedback table for both entry kinds mirrors `journal_comments`, whose ownership
  and coach-read predicates already exist; a second visibility model would drift.
- A static, cacheable endpoint keeps the tree out of the web bundle without a request
  per screen.

## Alternatives Considered
- **Reference tables (`muscle_regions/groups/heads`) seeded by migration** (the plan's
  first sketch): needs seeding and migrations for every change, and gains nothing while
  only code edits the tree. Rejected for now; the version stamp on every goal row keeps
  a later move possible.
- **Extending `exercise_catalog_entries.muscle_groups`**: free strings, no roles, no
  heads, no mesh ids, and not the key Quick Text and injury warnings use.
- **Goal columns on `master_workouts`**: mixes a coach annotation into the authoring
  row and its publish/duplicate paths; a separate table keeps the RLS and lifecycle
  explicit.
- **Feedback on `training_log_entries` only** (the plan's sketch): executions are the
  other half of the journal; one `(entry_kind, entry_id)` table covers both.
- **AI suggestion first**: costs, needs the gym's key, and is not explainable; kept as
  a later refinement.

## Consequences
- Adding a catalog exercise requires an `ExerciseTargets` entry (test-enforced).
  Changing the tree requires bumping `MuscleTaxonomy.version/0`; stored goals keep the
  version they were saved with, so a future migration or re-suggestion can find them.
- Member visibility of goals is enforced in the application (as for the workout
  itself); RLS confines rows to the gym.
- A goal-feedback row written on a voided training-log entry stays (the entry is kept
  too) but can no longer change; feeds and analytics must ignore voided entries.
- Coach reads of feedback go through the totals endpoints (addendum); P3-M3 analytics read it through the
  existing rung predicates.

## Implementation Notes
- Migration `20261110100000_create_workout_goals_and_goal_feedback.exs`. `workout_goals`
  is in the Workouts tenant data policy and the audit's ready tenant tables;
  `goal_feedback` is in the Journal policy (`rls: :user`) and the audit's personal tables,
  like `journal_comments`. Both store facades are in `@tenant_scoped_stores`.
- `SaveWorkoutGoals` marks `source: "suggested"` when the saved muscles and qualities
  equal the live suggestion (whatever the client claims), else `edited`. A PUT without
  `visible_to_members` keeps the saved value (hidden on a first save).
- The member goals endpoint answers `200 {"workout_id", "goals": null}` when goals are
  missing or hidden, so a hidden goal set and an absent one look the same; it is 404
  only when the workout is not a published workout of the gym.
- `ExerciseDescriptors.weighted_from_workout/1` resolves names leniently (plurals); the
  ADR-124 `from_workout/1` is unchanged.
- Feedback saved on an entry done in another gym, or without a workout, returns
  `goals: null` (goals are read in the request's gym).

## Addendum (2026-10-21): board 18 extras
The owner took every recommended extra on board 18 (plan §5a). Backend:

- **Gym default.** `wod_goals_visible_by_default` (default false) lives in
  `organization_settings.settings["workouts"]` (`Organizations.Domain.WorkoutSettingsPolicy`,
  like the join link), read by any staff member, changed with `manage_settings` through the
  admin settings section `workouts` (`GET`/`PATCH /api/org/:slug/admin/settings`). A workout
  with no goals of its own and nothing to inherit shows the suggestion with the toggle at this
  default, and a first save without `visible_to_members` stores it. No migration.
- **Inheritance.** A workout without goals of its own uses those of the nearest workout it was
  copied from along `source_workout_id` (at most five levels, only within the gym), with their
  visibility (`Workouts.resolve_workout_goals/2`). Member, feedback and staff reads resolve it;
  the staff read answers `saved: false, inherited_from: <workout id>`, and a save on the variant
  writes its own row (a first save keeps the inherited visibility). Class variants and member
  versions are such copies (ADR-125, `ProgramUserWorkout`), and so are the filed class and
  athlete copies (`FileWorkoutCopy.ensure_in_folder`); these now pass `copy_goals: false` so they
  follow later edits of the base instead of a snapshot. An explicit duplicate or "copy to
  folder" still copies the goals (decision 4). Scale levels are materialised on the fly from the
  same workout (`WorkoutMaterializer`, ADR-128), so every scale shares its goals.
- **Coach totals.** `GET /api/org/:slug/admin/workouts/:id/goal-feedback-summary`
  (`manage_workouts`) and `GET /api/org/:slug/admin/schedule/slots/:id/goal-feedback-summary`
  (`manage_workouts` or `run_classes`) return `{workout_id, [scheduled_class_id], entries, shown,
  felt_muscles: [{id, count}], felt_qualities: [{id, count}], goals_not_felt}`. Feedback rows are
  read in the caller's own session, so the existing `goal_feedback` coach read policies decide
  what counts (no second visibility model): staff without the coach role in the gym count
  nothing. Voided entries never count. Below three entries only `entries` is returned
  (`shown: false`, empty lists). Muscles roll up to groups, each entry counting a group once;
  `goals_not_felt` lists the groups of the goal's primary and secondary muscles nobody felt
  (stabilizers are not expected to be felt). A class's entries are training-log entries logged
  from it and executions timed from one of its bookings, whichever workout version they
  followed; its goals are those of the class's workout. Migration
  `20261111100000_add_goal_feedback_entry_scope.exs` adds the SECURITY DEFINER
  `palee_goal_feedback_entry_scope(kind, id)` (workout, class, voided of one entry); its body
  uses `$1/$2` because `bookings.kind` would shadow the `kind` argument.
- **Member switch.** `felt_prompt_without_goals` (default true) on `body_settings`, next to
  `journal_sections`, in `GET/PUT /api/me/body/settings` (migration
  `20261111100100_add_felt_prompt_without_goals_to_body_settings.exs`; the table's owner-only
  policy already covers it). Workouts with goals always offer «Τι ένιωσες;».
- Open: an owner or admin who is not also a coach sees `entries: 0` on the totals, as on any
  coach read of the journal; widening that is a journal-visibility decision, not a goals one.
