# ADR-100: Coach Client Scope and Head Coaches
Date: 2026-10-12
Status: Accepted

## Context
Nothing links a coach to their clients or classes: class series and slots
have no coach, assigned workouts have no coach, and every coach sees every
client. The rights report gives coaches their **own** clients and classes by
default, with owners or admins able to widen a coach to all clients.

## Decision
- **Coaching relationships.** A `Coaching` relationship links a coach to a
  client (member or athlete) in a gym: `coach_user_id`, `client_user_id`,
  `origin` (`assigned` by an owner/admin, `self_assigned` by the coach,
  `invited` by the coach), `started_at`, `ended_at`. A client can have several
  coaches; a coach many clients.
- **Classes.** Class series and scheduled classes get an optional
  `coach_user_id`; a series' coach is copied to its generated classes and can
  be overridden per class. Appointment slots already have a coach.
- **Scope.** `CoachScope` resolves a coach's own clients (active
  relationships) and own classes. Staff queries (directory, client profile,
  programming, form reviews, reply queue, nutrition plans, health, appointment
  slots, class rosters, check-in, coaching analytics) filter by it on the
  server.
- **Head coach.** A per-membership setting `coach_scope` (`own` default,
  `all`) that only owners and admins change. It widens the coaching
  capabilities to every client and class of the gym, nothing else.
- **Self-assignment.** A coach may take an **athlete** (never a member) as a
  client. Owners and admins of the gym get a `coach_client_assigned`
  notification naming the coach and athlete.
- **Invitations.** A coach may invite clients as member or athlete; on
  redemption the client gets a relationship with that coach (`origin =
  invited`).
- **Money.** Coaches see only membership status for their clients (active,
  frozen, expired, package name, sessions left), through a status read model.

## Rationale
Explicit relationships make scope enforceable and auditable on the server and
give the coach a meaningful "my clients" list. Coach-on-class reuses the
schedule instead of inferring coaching from bookings. A single head-coach
toggle covers the senior-coach case without per-permission settings.

## Alternatives Considered
- Deriving a coach's clients from who booked their classes: rejected; members
  attending a class are not personal clients and history would leak.
- Per-client sharing settings: rejected as too fine-grained for gyms.

## Consequences
Owners and admins must assign coaches to classes and clients for scoped
coaches to see anything; until then a coach sees an empty client list, which
the UI explains. Existing data gets no relationships; the migration does not
guess them.

## Implementation Notes
Implemented in `0f8f700`, with web panels in `4a44f1e`.

- Migration `20261013110000_add_coaching_relationships_and_class_coaches`
  adds `coaching_relationships` and `coach_user_id` on class series and
  scheduled classes. `CoachScope` filters the staff queries listed above.
- `ManageCoachingRelationships`: owners and admins assign any coach to any
  client; a coach takes an athlete (never a member), which sends
  `coach_client_assigned` to the gym's owners and admins; a redeemed coach
  invitation creates an `invited` relationship.
- Head coach: `coach_scope` on the membership, set from the user profile by
  owners and admins.
- Web: a coach assignment panel on the client profile
  (`CoachAssignmentPanel.tsx`) and a coach select on classes
  (`ScheduleConsole.tsx`). Coaches see membership status only.
