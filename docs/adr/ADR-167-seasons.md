# ADR-167: Seasons — fixed-length programmes a gym sells
Date: 2026-10-21
Status: Accepted

## Context
Phase 3 (plan `docs/plans/redesign-phase-3-depth.md`, milestone P3-M5, decision D5) gives the
owner something new to sell: a season, a fixed-length programme such as «Hyrox prep» or a
12-week challenge. A season has dates, a number of places, a price, coaches and a programme
of workouts. Members find it in `Box › Συνδρομή`, ask for a place, and a confirmed member
gets the programme in Box and Ημερολόγιο and a crew to train with.

D5 fixes the commercial shape: a season is a package with dates and capacity; buying is a
request that staff confirm, exactly like today's packages, because there is no card
processor. So the feature has to reuse what exists rather than add a parallel model:
Finance packages and subscriptions (ADR-097 family) for what the member bought, assigned
workouts (ADR-125) for the programme, the gym club's channels (ADR-138) for the crew, and
the notification types pattern for the request and its answer.

## Decision
1. **A `Seasons` context with two tenant tables.** `season_offerings` (title, description,
   welcome message, `starts_on`, `weeks` 1..52, `capacity` 1..500, `price_cents`, currency,
   optional `membership_package_id`, `programme` jsonb of `{day, workout_id}`, `coach_ids`,
   `status` draft|published|running|completed|cancelled, `channel_id`) and
   `season_enrollments` (one row per member and season, status
   requested|waitlisted|active|declined|cancelled|completed, who decided and when, an
   optional decline reason). Both have RLS (enable + force, tenant policy and the
   `apply_tenant_context` trigger), a tenant data policy (purge order 86) and audit entries.
   Pure rules live in `Seasons.Domain.SeasonRules` and `EnrollmentLifecycle`.
2. **Enrollment lifecycle.** A request holds a place; when the held places
   (requested + active) reach capacity the request is **waitlisted** instead. Staff
   **confirm** (requested → active) or **decline** (requested|waitlisted → declined, with an
   optional reason the member sees). A member may **withdraw** a request or a waitlist place;
   a confirmed place is cancelled by staff (**remove**). Whenever a held place frees up, the
   earliest waitlisted member is promoted to requested and staff are notified. Declined and
   cancelled members may ask again. Every change runs under a per-season advisory lock.
3. **Confirmation does three things in one transaction:**
   - **Finance:** when the season names a package, `AssignFinanceMemberPackage` creates a
     subscription for the season's dates with the season's price as the price snapshot, so
     invoices, payments and entitlements follow the existing package flow.
   - **`#season` channel:** the first confirmation creates one invite-only channel of kind
     `season` inside the gym club (context `season_offering`), stores its id on the
     season and pins the gym's welcome message as a staff post. Each confirmed member is
     added with `source: auto`; a removed member leaves it.
   - **Programme:** each `{day, workout_id}` becomes an assigned workout on
     `starts_on + day` for the member, from the later of the start and today, tagged with
     `season_offering_id`.
4. **Status from dates.** `running` and `completed` are derived from `starts_on`/`weeks` on
   every read, and a daily sweep (`SeasonSweepJob`, 01:10) writes them down: participants
   complete, open requests are cancelled and the season's channel is archived.
5. **Schedule lock.** Start date, weeks and programme lock once anyone is confirmed;
   capacity can't drop below the participants; a season with requests can't go back to
   draft; a completed or cancelled season can't change. Cancelling a season cancels every
   request and place, removes future programme workouts and archives the channel.
6. **API.** Member: `GET /api/org/:slug/me/seasons`, `POST …/me/seasons/:id/request`,
   `POST …/me/seasons/:id/cancel`. Staff: `GET|POST /admin/seasons`,
   `GET|PATCH /admin/seasons/:id`, `POST /admin/season-enrollments/:id/confirm|decline|remove`.
   Reading needs `view_package_catalog` or `take_payments`; building needs `manage_packages`;
   answering requests needs `take_payments` or `manage_memberships`. The staff list also
   returns the coach candidates (the gym's staff).
7. **Notifications.** `season_requested` (to staff with `take_payments` and the season's
   coaches; also on waitlist and promotion), `season_confirmed`, `season_declined` (with
   the reason) and `season_cancelled` (to the member). Push text via `PushMessageBuilder`
   and gettext in 12 locales; the web bell words them from the `Seasons` namespace. Staff
   open `/admin/finance?tab=seasons&season=ID`, members `/box?season=ID`.
8. **Web.** One list and one sheet on each side: `Finance › Seasons` (list + side panel that
   builds the season and answers requests), and in `Box › Συνδρομή` a single line that
   opens a sheet with the gym's seasons and a season's detail («Ζήτα θέση» / «Απόσυρση» and
   where the request stands). Season workouts carry «Σεζόν · <title>» in Box today, the
   programme list and panel, and on the execution entries in Ημερολόγιο.

## Rationale
Reusing packages, assigned workouts and club channels means a season needs no new payment,
programming or chat machinery: staff confirm a place where they already confirm packages,
members train it where they already train, and finance reports already count it. Deriving
running/completed from the dates keeps every read correct even before the nightly sweep.

## Alternatives Considered
- **A club of kind `season` per season** (plan text offered either). Rejected: a second club
  per season adds a top-level entry to every participant's Clubs list and its own
  membership and moderation surface; a channel inside the gym club gives the same crew space
  with less clutter and reuses the gym club's moderation and staff roles.
- **A season as a special package type.** Rejected: packages have no dates, programme,
  coaches or capacity; bolting those onto every package would clutter the package wizard.
  The season instead *references* a package for the money side.
- **Members cancel a confirmed place themselves.** Rejected: money has changed hands; the
  member settles it with the box and staff use «Αφαίρεση».
- **Card checkout.** Out of scope (D5, no processor); open question 4 in the plan stays.
- **A programme as a separate stored entity (`programme_id`).** Rejected for now: a season's
  programme is a short ordered list of published workouts; a jsonb list validated by the
  domain keeps it with the season. A reusable programme library can replace it later
  without changing the scheduling step.

## Consequences
- `assigned_workouts` gained `season_offering_id`; the uniqueness index
  `assigned_workouts_workout_date_notes_index` now includes it (nulls not distinct), so a
  season's workout never merges into a personal assignment of the same workout and day.
- Removing a member deletes their season assignments from today on (an assignment left
  without athletes is deleted); past ones stay in their history.
- Removing a member or cancelling a season does not touch their Finance subscription:
  refunds and credits stay a staff decision in Finance.
- A season without a package is free of finance side effects (the gym tracks payment
  outside Finance); with a package the price is the season's, not the package's.
- The `#season` channel is visible only to its participants and staff (`ClubScope`), so
  other members of the gym club never see it.
- Follow-ups: card payment (open question 4), a programme library, and a season card in
  discovery surfaces if gyms ask for it.

## Implementation Notes
- The welcome message is the gym's own text, so the server never has to localise it;
  without one the description or title is pinned.
- Confirm checks, in order: the season is open, a place is free, the transition is valid,
  then grants the package, ensures the channel, joins it, schedules the programme and
  finally writes the transition; any failure rolls the whole step back.
- The member's season list shows open seasons plus any season they hold a request,
  waitlist, place or completion in; drafts are never shown.
- Ημερολόγιο labels come from `Seasons.assignment_seasons/2`, read in each gym's tenant
  context the execution history already resolves (one query per gym per page).

## Decisions
- `#season` is a channel in the gym club, not a club: least clutter, reuses gym-club moderation.
- Channel is invite-only, visible to participants and staff only: the crew space is the participants'.
- Channel is archived (not deleted) after the season: history stays readable for those who were in it.
- Welcome message is written by the gym and pinned by staff: no server-side localisation, gym's own voice.
- Price lives on the season and overrides the package price on the subscription: one season can reuse a generic package.
- Package is optional: a gym can sell a season without touching Finance.
- Requested and active both hold a place: staff never confirm more people than places.
- Full seasons waitlist instead of refusing: freed places go to the earliest waitlisted member automatically.
- A promoted waitlist member becomes "requested", not "active": staff still confirm because money is involved.
- Members can't cancel a confirmed place: refunds are settled with the box; staff remove.
- Running/completed are derived from dates on read plus a nightly sweep: correct at any time, cheap to store.
- Start date, weeks and programme lock after the first confirmation: participants' calendars and subscriptions never shift.
- Mid-season confirmation schedules from today: no back-dated workouts appear as missed.
- Season workouts are their own uniqueness key: they never merge with personal assignments.
- Programme is a jsonb list of published workouts: smallest model that works; a library can replace it.
- No season card in Γύρω μου or the public box page: requests need gym membership, so a card there would be clutter with no action; the plan's card is dropped.
- Builder lives in Finance next to Packages: seasons are something the gym sells.
- Member entry is one line inside the Συνδρομή card, shown only when there is a season: zero clutter for gyms without seasons.
- Season label on workouts in Box, programme list and Ημερολόγιο execution entries: the member always knows why a workout is there.
- Staff notified are those who can take payments plus the season's coaches: the people who confirm and the people who coach.
- Decline reason is optional and shown to the member: honest without forcing staff to explain.
- Playwright stub API on port 18342 for this milestone's runs: avoids colliding with other agents' stub servers on 18302.
