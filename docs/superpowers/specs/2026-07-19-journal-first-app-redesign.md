# Milos Training - Journal-First Product Redesign

**Date:** 2026-07-19  
**Status:** Approved product direction and cross-feature constraints; ADR codification remains required before implementation  
**Ground truth:** `/home/rodochrousbisbiki/MyApps/Milos - training journal feature design discussion.md`  
**Extends:** `docs/superpowers/specs/2026-06-05-gym-app-design.md`

## 1. Product Thesis

For an ordinary training user, Milos Training is first a durable personal training
memory. Coaching, gym community, class logistics, subscriptions, and programming
are valuable connected layers, but they are not prerequisites for using the core
product.

The primary user promise is:

> Record what you planned, what you actually did, how it felt, and what changed;
> retain a useful training history across time, devices, gyms, and coaches.

The main personal information architecture becomes:

1. **Today** - the fastest route from intent to an accurate record.
2. **Journal** - the chronological, searchable training record.
3. **Progress** - PRs, trends, workload, consistency, and derived insights.
4. **Community / Coach** - messaging, sharing, feedback, and collaboration.
5. **Gym** - schedule, bookings, attendance, subscriptions, and billing when linked.

Admin operational surfaces remain role-specific. An admin may also use the personal
training surfaces for their own training.

## 2. Non-Goals

This redesign does not:

- replace the coach workout builder with the personal logger;
- turn the Journal into an unstructured notes feed;
- copy every canonical entity into a generic journal table;
- treat a booking or assignment as proof that training occurred;
- rewrite a coach's prescription when an athlete records actual performance;
- move private coach notes into the athlete's personal Journal;
- make manual entries count automatically for leaderboards or challenges;
- provide medical diagnosis or treatment advice;
- promise cross-device availability before a local operation reaches the server.

## 3. Core Experience

### 3.1 Today is always writable

Every personal user sees a persistent Today capture surface, even when they have no
gym, coach, assignment, booking, or prior app-managed workout.

The primary actions are:

- Log workout
- Add note
- Add body update
- Add recovery

Wellbeing/readiness may appear as a compact structured prompt, not as a fifth
equal-weight entry type.

Saving one workout never removes the capture surface. A user can record multiple
workouts and other entries on the same day. The day groups records for display; it
is not an aggregate and does not impose one-record-per-day uniqueness.

### 3.2 Today proposes sources without guessing

Today composes plain candidate DTOs from Execution, Workouts, and Scheduling through
an Application Service. Candidate priority is used for presentation, never for a
hidden automatic assertion about what the user did.

| Situation | Today behavior | Permanent Journal behavior |
|---|---|---|
| Active execution | Offer Resume | Show as in-progress only if product policy enables it |
| Completed execution today | Show the actual result and edit link | Reference the execution once |
| Assignment due today | Offer prescription as a starting point | Create an actual log only after user confirmation |
| Booked class with published WOD | Offer the WOD as a starting point | Create an actual log only after user confirmation |
| Booked class without WOD | Prefill class metadata only | Never invent workout content |
| Multiple candidates | Require explicit source selection | Persist the selected source link |
| No candidate | Open an empty personal workout form | Create an independent workout |

`Log a different workout` is always available. Linked users can ignore a proposed
source, and all users can add another workout after completing the first.

### 3.3 Planned and actual are distinct

A source-backed journal workout contains:

- an immutable source identity;
- a prescription snapshot representing what was assigned/published at capture time;
- independently editable actual performance;
- an explicit provenance value;
- optional links to the assignment, class, booking, and execution that are still
  authorized for the viewer.

Journal edits cannot mutate a master workout, assignment, class WOD, or historical
timer/progress events. Completed app-managed executions continue to store actual
changes as ADR-050 structured modification patches. The Journal renders that
execution; it does not create a duplicate independent workout.

## 4. Canonical Personal Workout

The personal form uses progressive disclosure. Its initial state asks only for a
title, time, duration, perceived intensity, exercises/tasks, and optional notes.
Sections, formats, substitutions, detailed metrics, and source comparisons appear
only when relevant.

### 4.1 Workout fields

- `id`
- `owner_user_id`
- `occurred_at` plus the captured timezone/offset
- `title`
- `activity_type`
- `duration_seconds`
- `intensity_rpe`
- optional `location`
- `source_type`
- optional opaque `source_id`
- immutable `prescription_snapshot`
- `visibility`
- workout-level `notes`
- `client_operation_id` for idempotent creation
- `lock_version` for conflict-aware edits
- captured IANA timezone and occurrence-local date
- audit timestamps

Allowed initial source types are `independent`, `coach_assignment`, `class_booking`,
`class_wod`, `workout_execution`, and `imported`. An execution is normally a
referenced timeline source rather than an independently persisted journal workout.

### 4.2 Hierarchy

```text
Journal workout
  -> block (warmup, strength, conditioning, skill, accessory, cooldown, recovery)
    -> movement or task
      -> performance rows (set, round, interval, or attempt)
```

A block stores title, type, format, and position. A movement/task stores an exercise
catalog reference or custom name, position, measurement profile, prescribed defaults,
substitution metadata, and contextual notes.

### 4.3 Performance rows are the actual truth

Entering `5 sets` or `4 rounds` generates that number of independently editable
performance rows. The count is a row-generation instruction, not the final actual
result.

Each row has:

- stable ID and sequence;
- row kind: set, round, interval, or attempt;
- status: completed, partial, skipped, or failed;
- optional set/round/interval coordinates;
- typed nullable metrics: reps, load and unit, duration, distance and unit,
  calories, rounds, score, and RPE;
- optional notes.

For a circuit, rows may share a `round_index` while remaining attached to their
specific movement. This preserves both the round relationship and movement-level
actuals.

The form derives visible fields from a measurement profile:

- strength: reps, load, RPE;
- running: distance, duration, pace;
- machine: calories or distance, duration, resistance;
- isometric: duration, optional load;
- bodyweight: reps, assistance or added load;
- conditioning: elapsed time, reps, calories, rounds, score.

Users can add a relevant secondary metric. They are not shown a grid containing
every possible metric.

### 4.4 Fast entry and destructive changes

Defaults populate generated rows. Required editing controls are:

- Apply defaults to all rows
- Copy previous row
- Add set/round
- Mark partial, skipped, or failed
- Add a row note

Increasing the declared count appends rows. Decreasing it may remove only untouched
generated rows silently. If any removed row contains user-entered data, the UI must
ask whether to keep it as extra work or remove it. Server commands apply the same
invariant; this cannot rely only on frontend confirmation.

## 5. Journal Entry Taxonomy

The main capture surface presents four explicit entry types:

1. **Workout** - canonical independent or source-backed actual workout.
2. **Recovery** - mobility, stretching, physio, or another recovery activity.
3. **Body update** - structured observation about discomfort, limitation, or healing.
4. **Note** - free-text reflection, optionally linked to another authorized entity.

Readiness/wellbeing is a structured daily signal owned by the appropriate canonical
domain and projected into the Journal.

Free text remains available at the daily note, workout, movement, performance-row,
body-update, and recovery levels. Text is stored where its meaning belongs rather
than flattened into one daily blob.

## 6. Journal as a Canonical Timeline

The Journal is a chronological projection over authoritative records. It owns
personal notes, recovery entries, and independent/source-backed journal workouts.
It references facts owned elsewhere:

- Execution: started/completed workout executions and ADR-050 actual patches;
- Wellbeing: body reports, status changes, and readiness signals;
- Feedback: class/workout ratings and review text;
- Pantheon: personal records and score history;
- Gamification: sparse, meaningful milestones;
- Workouts/Scheduling: provenance links, not proof of completion.

The projection stores source identity and a minimal render snapshot for stable list
performance. The source context remains authoritative for permissions, mutations,
and detailed reads. Cross-context events carry plain maps; the Journal must not
import foreign Ecto schemas.

The Journal is a global personal vault, not an organization-owned aggregate. A
timeline item may carry optional organization provenance, but its owner is the global
Identity user. Tenant-owned executions, bookings, assignments, feedback, and
organization-authored safety records remain in their owning contexts.

Every timeline item is unique by `(owner_user_id, source_context, source_type,
source_id)`. Replaying a source event updates or no-ops the projection rather than
creating another card.

Assignments and bookings appear in Today's planned area only. They enter permanent
history after an execution starts/completes or the user confirms an actual log.
Derived events are deliberately sparse so the Journal does not become a noisy
activity feed.

When an organization membership ends, the user retains read-only access only to
their own actual training results. Prescription, class detail, other-member data,
coach-private data, and continuing tenant operations are no longer authorized.

## 7. Relationships Between Records

Journal relationships are explicit typed links, for example:

- body update -> workout -> movement -> performance row;
- PR -> workout/execution -> performance row;
- feedback -> class/booking -> execution;
- note -> workout, body issue, or conversation;
- recovery -> body issue.

Links use opaque context/type/ID tuples plus optional local coordinates. A link does
not grant access to its target. Each card and detail request applies the canonical
source's authorization policy.

The app never automatically merges a manual workout with a later execution. It may
suggest a link based on time/source similarity, but the user chooses `Link` or `Keep
separate`.

## 8. Notes, Injuries, Ratings, and Existing Surfaces

The consolidation rule is: one central input surface, specialized read surfaces
where they provide operational value.

| Existing concept | Canonical owner | Capture after redesign | Secondary view |
|---|---|---|---|
| Personal/daily note | Training Journal | Today/Journal | Journal search/day |
| Workout note | Journal or Execution aggregate | Workout editor/finish flow | Execution summary/Journal |
| Movement/set note | Journal or Execution aggregate | Adjacent to its target | Workout detail |
| Injury report | Wellbeing | `Body update` from Today/Journal | Body & Recovery trends |
| Injury healing/status | Wellbeing | Body update/detail action | Active issues |
| Readiness check-in | Wellbeing | Compact Today prompt | Trends/Progress |
| Class/workout rating | Feedback | Contextual completion/Journal action | Reviews/insights |
| Private coach note | Coaching | Coaching dossier only | Coach-only dossier |
| Booking comment | Scheduling | Booking flow | Booking detail |
| Direct message | Messaging | Messaging | Thread history |

The current `/wellbeing` form and home `WellbeingFormPanel` become one Journal Body
Update command surface. `/wellbeing` evolves into the Body & Recovery read/trend
surface. Review capture becomes contextual; review administration remains separate.
Execution's finish flow retains execution-owned score and actual-patch collection but
is visually integrated with the same workout-detail language.

Legacy records are preserved. Backfills create timeline references/projections, not
new duplicate canonical facts.

## 9. Privacy, Coaching, and Sharing

The Journal is locked and private by default. Organization role alone never grants
Journal access, including owner or admin roles.

`Coaching` owns organization-scoped, many-to-many coaching relationships. A
relationship requires mutual consent. The user selects one active relationship as
their chosen/default coach. That coach receives baseline read access to:

- the user's full PR and injury/body-update history;
- assignments and booked classes only from the relationship's organization;
- entries explicitly shared with that coach.

Changing the chosen coach revokes the previous coach's baseline, explicit shares,
and access grants. It does not delete canonical records.

Baseline visibility updates the coach's authorized Personal Journal view without
creating a notification. Only an intentional manual share creates an immediate
recipient notification.

The owner may explicitly share an entry with any active member of an organization
they share, regardless of role. An explicit share is revocable and creates an
immediate durable notification. Sharing one entity does not recursively share linked
entities. A shared workout may link to a private body report without exposing it.

Any active same-organization member may submit a structured Journal access request.
The requester chooses scope and expiry; possession of an account, role, or request
UUID does not grant access. The owner receives a notification with inline Approve
and Deny actions and an Adjust action that may narrow the requested scope.

The compact default request preset is the last 30 days of workouts and PRs. Body
updates, recovery, and notes require explicit selection under Customize. The owner
may explicitly include independent or other-organization entries. Grants are
read-only, expiring, immediately revocable, and evaluated against canonical source
permissions on every read. Private coach notes never enter a user Journal response.

No Journal-specific comments system is introduced. Access requests and approvals are
structured commands, not conversations.

## 9.1 Personal fact ownership

- Self-authored body updates and readiness facts are global user-owned Wellbeing
  records with optional organization provenance.
- Organization-authored injury/safety records remain tenant-owned Wellbeing records.
- PRs and PR history are global user-owned Pantheon records.
- Feedback remains owned by its target organization/context and is referenced by the
  timeline.
- Existing self/admin report provenance is used for additive migration; records are
  not duplicated into Journal-owned copies.

## 9.2 Removal, deletion, and revision history

Journal-native entries use Trash rather than immediate deletion. Trash hides an
entry immediately, permits restore for 30 days, and then purges content and owned
children through a durable job. Accepted edits retain immutable revision history and
use optimistic locking.

For a projected canonical card, `Remove from Journal` creates a reversible personal
suppression only. `Delete everywhere` is shown only when the owning context exposes
an authorized destructive command; that context's retention and audit policy remains
authoritative.

## 10. Offline and Multi-Device Semantics

Journal writes adopt ADR-067's durable, per-user IndexedDB outbox only after each
write command has an owning-context idempotency and conflict policy.

- Create commands use a client-generated UUID and a unique
  `(owner_user_id, client_operation_id)` constraint.
- The browser persists the full command before attempting the network request.
- Closing the app or signing out does not clear the device outbox.
- Reconciliation occurs after authentication, on `online`, and when a tab becomes
  visible.
- The server returns the canonical existing record for a duplicate create.
- Edits carry `lock_version`; the server rejects stale edits with a structured
  conflict instead of silently overwriting another device.
- The UI preserves the local draft and offers a field-aware conflict review.
- Permanent validation/authorization failures remain visible and require explicit
  user action.
- Journal-native creates and edits, explicit shares, and Journal access requests use
  opt-in durable outbox adapters.
- Trash, restore, purge, relationship changes, approvals, denials, and revocations
  require an online authorization check.

Before server acknowledgement, a draft exists only on its originating browser
profile. After acknowledgement, PostgreSQL is authoritative and all devices obtain
the record through normal Journal reads and realtime invalidation. Browser storage
is not described as a cloud journal and cannot survive user-cleared site data or
loss of the unsynchronized device.

## 11. Gamification and Progress

The Journal produces reliable facts before it produces rewards.

- Completed app-managed executions keep existing gamification semantics.
- Independent structured workouts can count toward private consistency/load trends
  after policy validation.
- Independent entries do not enter public leaderboards or competitive challenges by
  default.
- Notes, body updates, and recovery entries do not award workout completion credit.
- PR detection consumes typed actual performance and records provenance to the exact
  row where possible.
- A potential PR from a manual workout requires explicit user confirmation and is
  recorded with `self_reported` provenance.
- Self-reported PRs remain outside public leaderboards and competitive challenge
  credit.
- Coach analytics compare prescription snapshots with actual rows without mutating
  either side.

Progress is a read/insight surface derived from canonical Journal, Execution,
Pantheon, Wellbeing, and Gamification facts. It is not another data-entry surface.

## 12. UX and Accessibility Requirements

- Mobile is optimized for rapid one-handed logging; desktop may use denser tables.
- Performance-row dimensions are stable so adding data does not shift surrounding UI.
- Compact mobile rows expand for secondary metrics and notes.
- Icon buttons use the installed icon system and have accessible names/tooltips.
- Every generated row is keyboard reachable and has a programmatic set/round label.
- Draft, syncing, synced, conflict, and permanently failed states are visible without
  relying on color alone.
- The Today composer is a workspace, not a marketing hero or nested card stack.
- Locale, RTL, reduced-motion, and narrow viewport behavior are release gates.
- Medical wording describes observations and training impact, not diagnoses.

## 13. Multi-Tenant and Catalog Constraints

Milos Training uses one browser origin and one deployment. Personal routes such as
`/today`, `/journal`, and `/progress` are user-scoped. Organization routes use
`/org/:slug/...`; the application router changes these paths through normal in-app
navigation, and users never need to type an endpoint.

The path selects tenant context but never grants access. Every organization-scoped
HTTP, Channel, job, cache, search, and object-storage operation validates the active
membership. Personal operations validate the global user and applicable grants.
Hidden selected-organization session state is not authoritative, so bookmarks,
refreshes, and tabs may safely use different organizations.

Independent users may register at the personal application without an organization
membership and later join organizations through invitations.

`Workouts` becomes the canonical owner of the existing movement catalog. The same
movement identity is used by personal workout rows and PR definitions. A versioned
JSON seed is loaded idempotently into PostgreSQL, and Meilisearch provides fuzzy
suggestions over approved canonical terms and aliases.

Unmatched text is always retained in the user's record but excluded from analytics
until approved. Source-backed submissions enter the source organization's moderation
queue; independent submissions enter the platform queue. Tenant approval makes a
term analytics-valid only inside that tenant. An audited platform-owner promotion
makes it global. Rejection never removes the user's original text.

## 14. Required Architecture Decisions

Before the first Journal migration, accepted ADRs must codify these approved choices:

1. Add `MilosTraining.TrainingJournal` for independent workouts, recovery, personal
   notes, links, revisions, grants, suppressions, trash, and the timeline projection.
2. Treat Journal-native records, self-authored Wellbeing facts, and Pantheon PRs as
   global user-owned resources protected by user-scoped RLS. Optional organization
   provenance never changes their owner.
3. Keep Execution, Scheduling, Feedback, and organization-authored Wellbeing facts
   tenant-owned and accessible only through public context contracts.
4. Use mutually accepted Coaching relationships plus explicit Journal shares and
   scoped access grants; never infer Journal access from an organization role.
5. Use transactional local writes and durable, idempotent projector jobs for timeline
   updates. REST is the full-payload source of truth; Channels invalidate/refetch.
6. Transfer canonical movement-catalog ownership from Analytics to Workouts without
   creating a duplicate catalog table.

The multi-tenant implementation and ADRs must be completed first. Journal
implementation branches from that accepted foundation; no Journal schema should
encode a tenant-only personal ownership assumption.

## 15. Success Criteria

The redesign succeeds when:

- an independent user can create a structured workout in under a minute;
- a linked user can start from an assignment or class WOD and record different
  actual values per set/round without changing the prescription;
- multiple same-day workouts and notes are represented without duplication;
- app-managed executions, body reports, ratings, and PRs appear once in a coherent
  chronological history with correct deep links;
- injury/body capture exists in one place while active-issue tracking remains useful;
- a queued offline create survives close/sign-out and converges exactly once after
  reconnection;
- a stale offline edit never silently overwrites a newer server version;
- private linked records are not leaked through Journal cards or sharing;
- existing execution, injury, feedback, PR, and coach-note histories remain intact;
- independent users can register and use the personal app without a synthetic tenant;
- organization navigation stays in one browser origin and never depends on manually
  typed URLs or hidden tenant state;
- chosen-coach, explicit-share, and requested-access permissions match the approved
  matrix and revoke immediately;
- custom movement text remains visible while analytics include only appropriately
  approved catalog identities;
- personal users understand Milos Training's first screen without needing a gym or
  coach relationship.
