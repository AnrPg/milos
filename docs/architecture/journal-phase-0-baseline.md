# Journal Phase 0 Baseline

Date: 2026-08-04
Status: Reviewed baseline for ADR-086 and Phase 1 implementation

This document closes the Phase 0 inventory, glossary, invariant, retention,
timezone, and rollout checklist for the journal-first redesign. It is a planning
artifact only; production schema and route changes begin in Phase 1 after
ADR-086.

## Accepted Decision Gates

| Gate | Decision | Phase 1 constraint |
|---|---|---|
| Gate A - `TrainingJournal` bounded context | Accepted | Add a first-class `MilosTraining.TrainingJournal` context for journal-native records and timeline projection. |
| Gate B - coach sharing authorization | Accepted | Do not infer Journal access from admin or owner role; require chosen coach relationship, explicit share, or scoped grant. |
| Gate C - independent personal users | Accepted | Every authenticated user may use personal Journal surfaces without a synthetic organization membership. |
| Gate D - timeline consistency | Accepted | Use transactional local writes plus durable idempotent projector jobs; channels invalidate, REST reads. |

## Domain Glossary

| Term | Definition | Owner |
|---|---|---|
| Today | The current-day personal workspace that shows capture actions, planned candidates, readiness prompt, and already recorded entries. | Application composition over multiple contexts |
| Journal | The chronological, searchable personal training record made from Journal-native records and authorized projected source facts. | `TrainingJournal` timeline projection plus source contexts |
| Planned candidate | A plain DTO suggesting an active execution, due assignment, booked class, or published WOD as a starting point. It is not proof of completion. | Application service |
| Prescription snapshot | Immutable plain data copied from an authorized assignment/class WOD/workout at capture time. Later edits never mutate the source prescription. | `TrainingJournal` for journal workouts; `Execution` for executions |
| Actual workout | What the user says they did. For app-managed timers this remains the execution plus ADR-050 patches; for non-execution logs this is a journal workout. | `Execution` or `TrainingJournal` |
| Journal workout | A Journal-owned actual workout with blocks, movements/tasks, rows, source metadata, visibility, revisions, trash state, and optional links. | `TrainingJournal` |
| Block | A positioned workout section such as warmup, strength, conditioning, skill, accessory, cooldown, or recovery. | `TrainingJournal` |
| Movement/task | A positioned exercise or task inside a block, with canonical catalog ID or retained custom text, measurement profile, prescribed defaults, substitution data, and notes. | `TrainingJournal` |
| Performance row | The actual truth for one set, round, interval, or attempt, with independent status, metrics, RPE, score, and notes. | `TrainingJournal` |
| Body update | A structured observation about discomfort, limitation, healing, or readiness. Self-authored facts are global personal Wellbeing records projected into Journal. | `Wellbeing` |
| Recovery entry | Journal-native mobility, stretching, physio, or recovery activity that can link to workouts or body issues. | `TrainingJournal` |
| Personal note | Journal-native reflection not already owned by execution, booking, review, message, or coach-private note surfaces. | `TrainingJournal` |
| Source link | Opaque context/type/id plus optional local coordinates. A link never grants access to the linked target. | `TrainingJournal` stores link; source context authorizes target |
| Timeline item | Owner-scoped read projection card keyed by source identity and containing minimal render snapshot plus deep-link metadata. | `TrainingJournal` projection |
| Visibility | Private default, explicit coach/share/grant access, and future sharing policies evaluated at read time. | `TrainingJournal` plus `Coaching` public authorization |
| Organization provenance | Optional organization metadata describing where a fact came from. It does not change personal ownership or grant access. | Source context and `TrainingJournal` metadata |
| Suppression | Reversible owner preference to hide a projected source card from Journal without deleting the source fact. | `TrainingJournal` |
| Trash | Reversible deletion state for Journal-native records; hidden immediately, restorable for 30 days, then purged by job. | `TrainingJournal` |

## Executable Invariant Names

These names are the Phase 1 red tests to create before migrations or production
modules. They are written as ExUnit test names so the implementation can copy them
directly into focused domain and integration suites.

### Domain tests

File target: `apps/api/test/milos_training/training_journal/domain/journal_workout_builder_test.exs`

- `test "rejects a workout with no meaningful actual content"`
- `test "generates stable performance rows from set defaults"`
- `test "generates stable performance rows from round defaults"`
- `test "preserves populated rows when a declared count decreases without explicit removal"`
- `test "removes only untouched generated rows when a declared count decreases"`
- `test "permits different metrics statuses and notes on every performance row"`
- `test "validates strength measurement metrics and units"`
- `test "validates running measurement metrics and units"`
- `test "retains custom movement text when no catalog identity matches"`
- `test "preserves immutable prescription snapshots across actual edits"`
- `test "validates source link cardinality and provenance"`
- `test "permits multiple workouts and notes for the same owner local date"`
- `test "defaults journal-native entries to private visibility"`
- `test "validates typed links without granting target authorization"`
- `test "groups entries by captured occurrence local date rather than current timezone"`

### Integration and boundary tests

File target: `apps/api/test/milos_training/training_journal/training_journal_test.exs`

- `test "idempotent create returns the canonical record for the same owner operation"`
- `test "idempotent create does not converge across different owners"`
- `test "stale lock version update returns a structured conflict"`
- `test "timeline projection is unique by owner source context source type and source id"`
- `test "projected source suppression does not delete the canonical source"`
- `test "journal-native trash hides immediately and restore revives before purge"`
- `test "personal reads require owner or explicit grant"`
- `test "organization provenance alone does not authorize a tenant reader"`

File target: `apps/api/test/milos_training/application/get_today_journal_test.exs`

- `test "returns resume candidate for an active execution"`
- `test "returns completed execution as recorded history not a new actual"`
- `test "returns assignment candidate without creating journal history"`
- `test "returns booking with published wod as an explicit starting point"`
- `test "returns booking without wod as metadata only"`
- `test "requires explicit source selection when multiple candidates exist"`
- `test "always returns a different workout capability"`
- `test "handles timezone day boundaries from requested local date"`

## Legacy Surface Matrix

| Surface | Current role | Classification | Phase 0 decision | Replacement path |
|---|---|---|---|---|
| `/` authenticated landing | Personal stats, WOD history, PRs, wellbeing prompt, role/admin content | Embed | Keep while feature flag is off; under flag, Today becomes the personal workspace and admin content remains reachable. | `/today` or personal mode at `/`; admin destinations stay in role nav |
| `WellbeingFormPanel` on home | Injury/body capture | Remove after migration | Do not keep as a second create form after Body Update composer ships. | Today Body update composer, `/wellbeing` trends/read surface |
| `/wellbeing` create form | Injury report and healing capture | Redirect/embed | Convert to Body & Recovery read/trend surface; create actions deep-link into Journal composer. | `/journal?compose=body_update` and issue detail actions |
| `/my-workouts` or workout history panels | Execution/WOD history | Embed/read-only | Move history presentation into Journal while retaining source-owned execution details. | Journal timeline cards linking to execution detail |
| Execution finish flow | Score and ADR-050 actual patches | Retain/embed | Keep Execution as canonical owner; align visual language with personal composer. | Execution detail card projected once into Journal |
| Execution detail/history | Source-owned actual result | Retain/read-only from Journal | Keep detail route authoritative; Journal links into it and suppresses duplicate cards. | Journal timeline source link |
| `/reviews` user capture | Feedback capture after contextual activity | Embed | Keep Feedback authoritative; move user entry points into contextual completion/Journal actions. | Journal/contextual review action |
| Admin review management | Operational triage | Retain | Remains admin surface; not part of personal Journal capture. | Admin routes |
| Pantheon PR panels | Personal records and history | Embed/read-only | Keep Pantheon authoritative; Progress reads and Journal cards reference exact PR/history facts. | `/progress` and Journal PR cards |
| Coaching dossier | Coach notes and athlete analytics | Retain | Coach-private notes never enter Journal payload; may link to Journal item from coach side only. | Coaching routes through explicit authorization |
| Schedule/booking | Class logistics and booking comments | Retain/embed | Bookings appear in Today's planned area only; permanent history starts after execution or explicit actual log. | Today candidate cards and Gym schedule |
| Assigned workouts | Coach prescription | Retain/embed | Assignments are candidates/prescriptions; actual changes create Journal workout or Execution patches. | Today candidate source selection |
| Messaging | Conversations | Retain | Remains its own active workspace and durable outbox owner; Journal links may reference conversations without copying messages. | Community/Coach nav |
| Notifications | Passive updates | Retain | Journal shares/access requests create notification facts, but notifications do not own Journal data. | Notification inbox/deep links |
| Finance/billing | Tenant subscriptions and accounting | Retain | Gym relationship surface, not Journal. | Gym/account billing |

## Retention, Export, and Timezone Semantics

- Journal-native records use Trash: hidden immediately, restorable for 30 days,
  then purged with owned children by durable job.
- Projected canonical source cards use owner suppression. Deleting the source is
  handled only by the source context's authorized command and retention policy.
- Revision history is immutable for accepted edits and must preserve before/after
  payloads enough to explain conflicts and audits.
- Data export includes Journal-native records, revisions, links, suppressions,
  shares/grants, and authorized source references. It must not include
  coach-private notes or tenant source details the user is no longer authorized
  to read.
- Occurrence storage includes UTC timestamp, captured IANA timezone, captured
  offset, and occurrence-local date. Journal day grouping and Today queries use
  occurrence-local date.
- Offline drafts are local to one browser profile until server acknowledgement;
  exports include only acknowledged server records.

## Rollout Flags and Rollback

| Flag | Default | Enables | Rollback behavior |
|---|---|---|---|
| `journal_context_enabled` | Off | TrainingJournal API/context routes after Phase 2 | Disable writes; existing data remains readable only through admin/debug tooling until re-enabled. |
| `today_journal_enabled` | Off | Today candidate API and personal workspace | Return to current landing page and legacy capture entry points. |
| `journal_timeline_projection_enabled` | Off | Cross-context projector jobs and timeline cards | Stop new projection jobs; canonical source records remain untouched. |
| `journal_offline_commands_enabled` | Off | ADR-067 outbox adapters for Journal commands | Keep online writes available; queued local records stay pending/failed until flag re-enabled or user removes them. |
| `journal_legacy_redirects_enabled` | Off | Redirects/deep links from legacy capture surfaces | Restore legacy pages while preserving new data. |
| `journal_sharing_enabled` | Off | Explicit shares, grants, and access requests | Hide sharing controls; preserve existing grants for read enforcement until revoked/expired. |

Rollout order is internal owner testing, selected users, then all users. Legacy
create surfaces are removed only after backfill counts, privacy tests, offline
tests, and live mobile/desktop evidence pass.
