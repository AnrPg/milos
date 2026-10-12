# ADR-115: Personalized Member Programming
Date: 2026-10-12
Status: Accepted

## Context
The design document separates two customer roles: a **Gym Member** books
classes and trains from class workouts, while an **Athlete** receives bespoke
programming through `/my-workouts`. ADR-071 kept that line explicitly: when a
coach programs a member from the admin user profile, the copied workout replaces
the workout of a class the member booked, and "direct member workout
assignments were rejected for now" (TD-037).

Owners now sell hybrid products: a gym member who attends classes but also pays
for personal programming, or who needs an individual variation of a class
workout (an injury, a competition taper, a beginner progression). Today the only
options are to change the class workout for every attendee or to convert the
member into an athlete, which cancels their bookings (ADR-095 role transition
reconciliation) and removes the schedule from their navigation.

Several mechanisms already exist and must not be duplicated:

- The assignment aggregate (`assigned_workouts` + `assigned_workout_athletes`)
  owned by Workouts, with per-assignee status (accepted/rejected/archived),
  per-assignee reschedule date, notifications, realtime refresh and the
  embedded authoring flow of ADR-039.
- Copy-on-programming (ADR-071): a programmed workout is a duplicate of a
  library workout, with `source_workout_id` provenance, published into the
  shared library.
- ADR-040 package contracts. The closed vocabularies already include the
  `personal_programming` channel, the `execute_assigned_workouts` and
  `receive_coaching_touchpoints` capabilities and the `coaching_touchpoints`
  allowance. Assignment creation already reserves and finalizes one
  `programming_delivery` touchpoint per assignee, and execution of an
  `assigned` source already requests `personal_programming` +
  `execute_assigned_workouts`.
- ADR-029 / F-03 execution source authorization (`AuthorizeWorkoutExecutionSource`)
  binds an `assigned` execution to an assignment link of the acting user.
- ADR-050 actual-workout patches describe what a person *did* differently after
  the fact; they are not a prescription channel and do not solve this.

## Decision
Personalized member programming reuses the existing assignment aggregate. An
assignment may target members as well as athletes, and may optionally be a
**class variant**: a per-member version of a class workout linked to the source
class occurrence.

### Ownership and data
- Workouts keeps owning assignments. `assigned_workout_athletes.athlete_id` is
  reinterpreted as the *assignee user id* (column names are kept; migrations
  are additive only). The public API keeps the `athlete_ids` field name for
  compatibility and documents it as "assignee user ids (athletes or members)".
- One additive, nullable column `assigned_workouts.source_scheduled_class_id`
  (exposed as `source_slot_id`) marks a class variant. It is a loose reference to
  a Scheduling-owned row (no cross-context foreign key, like ADR-108's
  `source_reference_id`). The derived `assignment_kind` is `class_variant` when
  the source slot is set, otherwise `personal`.
- The workout of a variant is an ordinary library copy (ADR-071): staff either
  copy the class workout as-is, or duplicate it into a draft, edit it in the
  embedded canvas (ADR-039) and publish it, then assign it. The copy records
  `source_workout_id`; the class keeps its own workout untouched.

### Who may be targeted
A pure Workouts domain policy (`AssignmentAudiencePolicy`) classifies assignees
by their **active membership role in the acting tenant** (never the global
account role, F-29):
- `athlete` and `member` are valid assignees; staff roles and non-members are
  rejected with the existing `invalid_athletes` code (message broadened).
- A class variant must target exactly one assignee, that assignee must be a
  member, and the member must hold an active (pending or approved) booking for
  the source class. Violations return `class_variant_requires_single_member`
  or `slot_not_booked_by_member`.
- Merging an assignment into an existing one with the same workout/date/notes
  (existing store behaviour) only happens when both share the same source slot,
  so a variant never silently loses its class link.

### Entitlement
Members do **not** receive personal programming by role. Before any write (and
before any library copy is made), assigning to a member requires an **explicit**
package grant: the member's effective Finance entitlement must include channel
`personal_programming` and capability `execute_assigned_workouts`. This check
uses the existing `EntitlementPolicy` evaluated in its strictest mode
(`authorize_explicit/2`: no `observe` leniency, no missing-profile pass, no
admin bypass), because the rollout modes of ADR-040 exist to keep historical
athlete programming working and no member has historical programming to
protect. A denial returns `member_programming_not_entitled` (HTTP 403) with the
member nickname and the underlying Finance reason. No new channel, capability or
allowance value is introduced.

After that gate, members and athletes follow the identical ADR-040 saga: one
`coaching_touchpoints` reservation per assignee (`programming_delivery`),
finalized when the assignment exists, released on failure, governed by the
tenant's rollout mode. When the allowance is exhausted, staff use the existing
audited per-user allowance extension. Per ADR-040, an extension never adds a
missing channel or capability, so a member without the channel must first be
given a package (or personal package) that includes `personal_programming`.

### Execution, gamification and attendance
Members start personalized workouts and class variants with the existing
`assigned` execution source. `AuthorizeWorkoutExecutionSource` now additionally
requires the acting user to hold an active `athlete` or `member` membership in
the assignment's organization (the link alone was previously sufficient), and
names the subject "assignee". Finance then evaluates the same
`personal_programming` / `execute_assigned_workouts` request as for athletes.
Completion flows through the unchanged completion pipeline, so streaks, totals,
badges, PRs and challenges count it like any execution. A variant execution is
**not** a class execution: it does not touch the booking, does not consume a
class visit and does not create or change attendance; staff still record class
attendance as before. A member may still execute the class workout through the
booking instead; both remain possible and each counts once as its own execution.

### Visibility
- `/my-workouts` (list, open, reject) is opened to members; reschedule and
  "request a workout" stay athlete-only. Members see their personal assignments
  and class variants there with role-aware copy, reusing the athlete console.
- The schedule calendar adds `my_version` to a slot for the member who owns a
  live (not archived, not rejected) variant of it — computed server-side for the
  acting user only, so no other member can see it. Staff instead receive
  `member_versions` (assignee, assignment, workout title) per slot.
- The admin user profile schedule for a member lists their assignments next to
  their booked classes, and its programming dialog offers three member modes:
  change the class workout for everyone (ADR-071 behaviour, still the default
  for compatibility), create this member's version of the class, or assign a
  personal workout without a class.
- The assignment board and quick-assign picker can include members
  (`GET /admin/athletes?include_members=true`), labelled by role.

### Notifications and realtime
The existing `workout_assigned` notification is delivered to every assignee
(members included) and links to `/my-workouts`. Staff realtime refresh uses
`TenantStaffRecipients` (ADR-104). No new notification type is introduced.

### Role transitions
Leaving the `member` role now also archives that user's live assignments in the
organization (mirroring what leaving `athlete` already does), in addition to
cancelling future bookings.

## Rationale
Reusing the assignment aggregate gives members every existing behaviour —
per-assignee status, notifications, messages, the board, analytics, execution
source binding, touchpoint metering — with one additive column. The ADR-040
vocabulary already describes exactly this product (`personal_programming`), so
gating on it keeps packages the single source of truth for what a customer
bought. Making the member gate strict while athletes stay mode-governed avoids
silently handing personal programming to every class member during the
`observe` rollout, without breaking any existing athlete flow.

A class variant as an assignment (instead of a Scheduling-side override) keeps
prescription ownership in Workouts, keeps the class workout untouched for every
other attendee, and lets the member execute their version through an already
authorized, metered source.

## Alternatives Considered
- **A parallel "member programming" aggregate** — rejected: it would duplicate
  assignment status, notifications, messaging, metering and execution source
  authorization.
- **Per-booking workout override in Scheduling** — rejected: Scheduling would
  own prescriptions, class executions would need a second workout per booking,
  and touchpoint metering would need a new saga.
- **ADR-050 patches as prescriptions** — rejected: patches record actual
  deviations after the fact; they are not addressed to the member beforehand.
- **A new `personal_member_programming` capability** — rejected: the existing
  `personal_programming` channel plus `execute_assigned_workouts` capability
  already mean "this customer bought personal programming"; a second value would
  force every package to be edited.
- **Letting member gating follow the rollout mode** — rejected: in `observe`
  mode every member would pass, which contradicts the product decision that
  members only get programming they paid for.
- **Allowing a per-user extension to grant the channel** — rejected: ADR-040
  explicitly keeps extensions to allowance units; channels come from packages.
- **Replacing the ADR-071 "change class workout" member mode** — rejected for
  this slice: it is an intentional, tested owner workflow; the new modes are
  added beside it and the UI makes the difference explicit.

## Consequences
- Every reader of assignments must treat `athlete_ids` as assignee ids; the
  admin board shows each assignee's role.
- `/my-workouts` list/open/reject accept members; the frontend shows "My
  workouts" to members.
- Slots in the schedule response may carry `my_version` (member) or
  `member_versions` (staff).
- Variants survive slot deletion (they become personal assignments whose
  `source_slot_id` no longer resolves); class cancellation does not delete a
  member's programming.
- Follow-up debt: member reschedule/request flows, a staff shortcut to create a
  variant directly from the admin schedule popup, and coaching aggregates that
  separate member from athlete programming.

## Convergence With the Multi-Role / Coaching Branch
A parallel branch (`claude/loving-franklin-vuxz19`, its ADR-098 "package
phase C" and ADR-100 "coach client scope and head coach") was not merged into
this work. This ADR deliberately does not touch the membership role model.
Overlap and how to converge after both land:

| That branch | This ADR | Convergence |
|---|---|---|
| `organization_memberships.roles` role sets | Assignee eligibility reads the single active membership role (`TenantAssigneeRoles`) | Replace the single-role lookup with "role set contains `athlete` or `member`"; `AssignmentAudiencePolicy.classify/2` stays unchanged if it receives the customer role. A person who is both should be classified as athlete (no explicit grant needed). |
| `coaching_relationships` + `CoachScope` filter staff programming queries | Staff routes stay owner/admin (unchanged pipelines); no coach scoping | `AssignWorkout`, `ProgramUserWorkout`, `ListAthletes` (`include_members`) and `member_versions` in the schedule should filter by `CoachScope` for coaches with `coach_scope = own`. Member programming is owner/admin-assigned; ADR-100's rule that coaches may self-assign athletes only is compatible. |
| Workout vault + `repeat` execution source | Member assignments execute through the `assigned` source | No conflict: completed member assignments appear in the vault as ordinary completed executions; a repeat of one uses `repeat`, not `assigned`, so it never re-checks the assignment. |
| Effective entitlement merges stacked/add-on subscriptions | `AuthorizeMemberProgramming` reads `Finance.get_effective_entitlement/2` | Picks up the merge automatically; a "personal programming" add-on on top of a class package will then enable member programming. |
| New channels (`personal_training`, …) and retired `workout_library` | Gate on `personal_programming` + `execute_assigned_workouts` | Unchanged vocabulary; no collision. |
| PT appointments / form reviews | Not touched | Independent. |

Migration ranges do not collide (this ADR: `20261012140000`).

## Implementation Notes
Implemented on 2026-10-12 (TD-037).

- **Migration** `20261012140000_add_source_scheduled_class_to_assigned_workouts`:
  one nullable column plus a partial index; no RLS change (the table is already
  forced-RLS and tenant-registered).
- **Domain**: `Workouts.Domain.AssignmentAudiencePolicy` (classification,
  class-variant rule, kind, live status, member programming modes,
  executable roles) and `Finance.Domain.EntitlementPolicy.authorize_explicit/2`;
  both unit tested.
- **Application**: new `TenantAssigneeRoles` and `AuthorizeMemberProgramming`;
  `AssignWorkout`, `UpdateAssignedWorkout`, `ProgramUserWorkout`,
  `AuthorizeWorkoutExecutionSource`, `GetAssignedWorkoutWeek`,
  `GetScheduleCalendar`, `GetAdminUserSchedule`, `ListAthletes` and
  `Organizations.Commands.SetMembershipRole` changed as described above. The
  workouts store exposes `list_class_variants/2` (query
  `Workouts.Queries.ListClassVariants`).
- **API**: the field is named `assignment_kind` (not `kind`) because the admin
  user schedule already uses `kind` = `class` | `assignment`. Profile
  programming accepts `mode`; `master_workout_id` became optional there (only a
  `class_variant` may omit it — it then copies the class's workout; other modes
  return `workout_not_found`). Assign accepts `source_slot_id`; `scheduled_for`
  stays required by the contract.
- **Emergent fixes**: `GET /admin/athletes` serialized `Identity.Account`
  structs, which have no JSON encoder, so the endpoint raised whenever an
  athlete existed. It now returns `{id, nickname, role}` with the membership
  role. `AssignWorkout` previously ignored membership status; assignees must
  now be *active* members of the tenant. Staff realtime refresh after an
  assignment uses `TenantStaffRecipients`.
- **Updates**: members newly added to an existing assignment must pass the
  explicit grant; like athlete additions on update, they are not metered
  (only creation reserves a touchpoint).
- **Frontend**: members get "My workouts" in the navigation and route guard;
  the console hides reschedule and "request a workout" for members and badges
  class versions. The schedule card shows "Your version" and the slot popup
  previews it with an "Open and start" link into `/my-workouts` (the existing
  start flow — no timer UI files were changed); staff see "Member versions" in
  the popup. The admin profile programming dialog offers the three member
  modes; "Edit class WOD for this member" duplicates the class workout into a
  draft and opens it in the embedded canvas (new `initialDraftId` prop), and
  publishing assigns it as the member's version. Assignee pickers include
  members with a "Member" badge. The home CTA also surfaces a member's
  assignment due today.
- **Deferred** (follow-up debt): member reschedule and "request a workout";
  a staff shortcut to create a variant straight from the admin schedule popup
  (today it is done from the member's profile); coaching aggregates that
  separate member from athlete programming; coach scoping after the coaching
  branch merges (see the convergence table).
