# ADR-253: The box screen («Οθόνη box»): pairing, today's screen, staff override
Date: 2026-10-29
Status: Accepted

## Context
CP-D1 (V3-M9): boxes want a TV on the wall that shows the day's WOD, who is
booked, a live leaderboard and the class timer, the way Wodify TV, SugarWOD's
whiteboard and PushPress's display do. A TV has no keyboard worth typing a
password on and no person signed in; it hangs in a room every member walks
through, so it must say as little about people as possible (GDPR data
minimisation). The product owner added (2026-10-29): staff choose from their
phone or the console what a screen shows (WOD, timer, leaderboard, bookings
or one class), pin it, optionally until a time, and «Επιστροφή στο
αυτόματο» returns it to the automatic flow; the TV changes at once and the
console shows who changed it.

Device pairing with a short code typed on the device follows OAuth's device
authorization grant (RFC 8628 §6.1: short, case-insensitive codes from an
alphabet without look-alikes, short lifetime, rate-limited attempts).

## Decision
1. **Context.** New bounded context `Palee.BoxScreens` with table
   `box_screens` (forced RLS, `palee_apply_tenant_context`): name (1–60),
   branch (`location_id`, null for the whole box), pending pairing code
   (only its SHA-256 and expiry), `token_version`, `paired_at`,
   `last_seen_at`, the override (`override_view`, `override_slot_id`,
   `override_until`) and who last changed what the screen shows
   (`focus_changed_by_id`, `focus_changed_at`). At most 20 screens per box.
2. **Pairing code («Κωδικός σύνδεσης»).** 8 symbols shown `ABCD-EFGH` from
   `ACEFGHJKMNPRTWXY34679` (no 0/O/D/Q, 1/I/L, 2/Z, 5/S, 8/B, U/V), drawn
   with rejection sampling from a CSPRNG, valid 15 minutes. Typing ignores
   case, spaces and dashes. Creating a screen returns its first code; `POST
   …/pairing-code` replaces any pending code, which is how a screen moves to
   another TV.
3. **Claim.** The TV is in no tenant when it types the code, so one narrow
   `SECURITY DEFINER` function, `palee_box_screen_pairing(hash, now)`
   (pins only `search_path`), maps an unexpired code's hash of an active box
   to `(organization_id, screen_id)`. The claim then runs in that box's
   tenant scope: the row is read `FOR UPDATE` with the hash and expiry checked
   again, the code is cleared, `token_version` goes up and `paired_at` is
   set, so a code pairs one device once and the previous TV's token stops.
4. **Display token.** Signed with the existing `SignedToken` port under its
   own salt (`box-screen-v1`): `{o: organization, s: screen, v:
   token_version}`, no person and no role, 90 days, renewed with `POST
   /api/box-screen/token`. Accepted only by `Plugs.AuthenticateBoxScreen`
   (`/api/box-screen/*`) and `/box_screen_socket`; Guardian and the user
   socket never accept it, and the box screen socket never accepts a
   session. Removing the screen deletes the row and closes its socket.
5. **Today (`GET /api/box-screen/today`).** On the box's own clock (its
   time zone; never UTC or a fixed zone): the classes of the screen's branch
   plus whole-box classes (every class for a whole-box screen), drafts left
   out, cancelled ones marked; each WOD once with its ADR-224 `body`; one
   leaderboard per WOD; bookings per class; and `focus`.
6. **Leaderboard.** The `#wod-σήμερα` card's ranking moves into
   `Application.WorkoutDayLeaderboard`, used by the card and the screen:
   results of the day (executions and log entries), never journal-private
   ones, only people in `leaderboard_opt_ins` (the card adds the viewer's own
   row as before). The screen also leaves out people who hide from members
   and shows the top 10.
7. **Privacy on the wall.** A person is shown by the first word of their
   display name only (bookings, leaderboard, coach). People with
   `hide_from_members`, guest and trial seats are only counted. Realtime
   hints never say who.
8. **Focus.** Automatic (`source: "auto"`): `timer` while a class runs (the
   class timer reused through `ClassTimerView` and the `class_timer`
   channel), `results` up to 30 minutes after it ends, `preview` of the next
   class, `idle` when the day is done; cancelled classes are skipped. Staff
   override (`source: "staff"`): `wod`, `timer`, `leaderboard`, `bookings`
   or `class`, optionally for one of today's classes on that screen
   (required for `class`) and until a time within 24 hours; an override that
   expired or whose class left the screen falls back to automatic.
9. **Realtime.** The TV joins `box_screen:<organization_id>` on
   `/box_screen_socket` and gets `box_screen:refresh` `{kind, slot_id}` from
   bookings, cancellations, attendance, cancelled classes, schedule changes,
   overrides and new results (a new domain event `workout_result_recorded`
   `{organization_id, workout_id, at}` published by `CompleteWorkout` and
   `LogTrainingEntry`); `box_screen:override` `{override}` reaches only the
   screen it is for (`handle_out`). It follows class timers on
   `class_timer:<slot_id>` for classes it shows. The application publishes
   on `Palee.PubSub` (`BoxScreenSignals`); `RealtimeEventHandler` delivers.
10. **Clock.** Every moment comes from the `BoxScreens.Ports.Clock` port
    (`:box_screen_clock`), so tests stand at any point of a class.
11. **API.** Staff, capability `manage_settings` or `manage_locations`,
    branch-scoped staff (ADR-186) only for their branches' screens:
    `GET/POST /api/org/:slug/admin/box-screens`, `PATCH/DELETE
    …/box-screens/:id`, `POST …/:id/pairing-code`, `PUT/DELETE
    …/:id/override`; creating screens and codes is limited to 30 POSTs an
    hour per person. TV: `POST /api/box-screen/pair` (no sign-in, 10 a
    minute per address, 201), `GET /api/box-screen/today` (120 a minute per
    screen), `POST /api/box-screen/token`, `GET
    /api/box-screen/classes/:slot_id/timer`. Errors: `invalid_pairing_code`
    422, `invalid_screen_name` 422, `invalid_screen_branch` 422,
    `invalid_screen_override` 422, `too_many_screens` 409,
    `box_screen_not_found` 404, `invalid_screen_token` 401.

## Rationale
A code typed on the TV needs no account on the device and no QR scanner, and
works on any smart TV browser or stick. Storing only the hash and spending
the code under a row lock keeps a leaked database row or a race from pairing
a second device. A version in the token makes "move to another TV" and
"remove" immediate without a token blacklist. The definer function answers a
single question with the code's hash as the only input, which keeps RLS
intact for everything else. Sharing the leaderboard keeps the card and the
wall from ever disagreeing on who may appear.

## Alternatives Considered
- **A staff member signs in on the TV**: puts a person's session (and its
  role) on a shared device in a public room.
- **QR code on the TV scanned by staff**: needs the TV to show a secret
  before it belongs to a box, and a camera flow on the phone; kept as a later
  convenience on top of the same claim.
- **Long-lived opaque device keys in a table**: works, but the existing
  signed-token port with a version gives revocation with no extra lookups.
- **Override as a separate table with history**: the console needs only the
  current choice and who made it; the audit of changes can come later.

## Consequences
- The screen UI (TV page, pairing screen, staff panel) is built later from
  the approved mockups; the API client is generated.
- `booking_made` and `booking_cancelled` now carry `scheduled_class_id`.
- Overrides do not expire by a job: the TV gets `focus.until` and reads
  `/today` again then; staff see the override as gone once it lapses.
- Coaches cannot pin a screen unless their role has `manage_settings` or
  `manage_locations` (an open question for the product owner; answered by
  the update of 2026-10-29 below).

## Implementation Notes
- Migration `20270209000000_create_box_screens`.
- Tenant data: `box_screens` is purged (order 6), the code hash never
  exported.

## Update 2026-10-29: the class's coach puts their class on the screen
Product-owner decision of 2026-10-29 (it answers the open question under
Consequences): a coach may change and pin what a box screen shows, but only
for their own class, from where they run it.

1. **Rule** (`BoxScreens.Domain.ClassScreenPolicy`, pure). A coach may pin
   `timer`, `leaderboard` or `wod` of a class when they coach it
   (`scheduled_classes.coach_user_id`), it is held today on the box's clock
   and not cancelled, and the screen is of the class's branch or the whole
   box (a whole-box class shows on every screen, as in Decision 5). The pin
   always carries the class's `slot_id`, so it falls back to automatic when
   the class leaves today's screen (Decision 8); `until` is allowed as for
   staff. A coach returns a screen to automatic («Επιστροφή στο
   αυτόματο») only while nothing is pinned or what is pinned is their
   class; they may pin over another choice. A coach of another class, a
   coach on another branch's screen or for another day's class, and
   members get 403 `forbidden`; a view a coach may not pin is 422
   `invalid_screen_override`.
2. **Staff rights unchanged.** `manage_settings` / `manage_locations` keep
   Staff › Box screens and may use the new endpoints for any screen of
   their branches with any view (branch-scoped staff as in Decision 11).
3. **Endpoints** (signed-in members of the box, next to the class timer
   remote; the service decides): `GET
   /api/org/:slug/class-timers/:slot_id/screens` (`{screens, views}`: the
   screens the person may change for that class), `PUT` and `DELETE
   /api/org/:slug/class-timers/:slot_id/screens/:screen_id/override`
   (`{view, until?}`). Same signals as the staff override: the paired TV
   hears it at once and the console shows who changed it.
4. **UI.** The class timer remote (`/class-timer/:slot_id/control`) gets
   «Στην οθόνη» («On screen»): a dialog with the class's screens, what each
   shows, the three choices and «Επιστροφή στο αυτόματο». It is hidden when
   no screen can show the class. Coaches never get the settings page.
5. **Layers.** `Application.BoxScreens.ClassScreens` (one service for
   `ClassScreenController`); the screen view and the TV announcement moved
   to `Application.BoxScreens.ScreenPresenter`, shared with
   `BoxScreenAdmin`.
