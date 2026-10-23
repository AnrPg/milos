# ADR-185: Event organisers («Διοργάνωση ως»), co-hosting and the organiser console
Date: 2026-10-23
Status: Accepted

## Context
Product vision M2: anyone should be able to host an event, as themselves or for a business. Until now
(ADR-153) an event belonged to a box's club and only box staff, or the admin of a member group, could
create one. Member-group events were forced to be free, members-only and without guest passes
(`EventPolicy.group_terms/1` plus a check constraint). Businesses that run an event together (a box and a
running club, a coach and a studio) had no way to show one event on both pages. Hosts also had no place to
run their events outside the gym's admin, and no numbers beyond the attendee list.

## Decision
1. **«Διοργάνωση ως» (Host as).** `POST /api/me/events` takes `host`: `"self"` («Ως εγώ») or the
   organisation id of a business where the person holds `manage_events`. `GET /api/me/event-hosts` lists the
   choices. «Ως εγώ» transparently creates a one-person organisation of `provider_kind: "organiser"` the first
   time (`EnsureOrganiserOrganization`). The person is its owner, and it gets the normal tenant defaults: its
   gym club, the free plan and a free slug. It stays `active` for demo mode (ADR-184) because it has no gym
   to try out. An advisory lock per person keeps it to one organisation. It reuses the tenant model as is,
   so RLS, export and purge, the staff event console and the feed all work without special cases.
   - **Clean-up rules.**
     - The organisation is created only after the event's form is valid, but the event can still fail after
       that, or be the only thing the person ever tried. A daily job (`OrganiserCleanupJob`, 04:35 UTC)
       archives organiser organisations that have never had an event and are more than 24 hours old. The
       definer function `palee_empty_organiser_organization_ids` lists them.
     - «Ως εγώ» again reactivates the archived organisation instead of creating a second one.
     - An organiser organisation that has had events is never swept. It stays like any dormant tenant
       (ADR-117), because its events, payments and attendees are records the host and the attendees keep.
2. **A person's own events.**
   - They are `open` (shown in Γύρω μου, posted to the host's followers' Feed as a public profile post with
     the event attached) or by invitation (`club`). The organiser club has only the host, so only people
     with the host's invite link come.
   - The host's invite link (`host_invite?`) admits anyone, with no guest count.
   - They never take guest passes or belong to a member group.
   - **Rate limits:**
     - At most 5 new events (a weekly run counts once) per 24 hours and 30 upcoming occurrences per host
       (`HostPolicy`, error `event_rate_limited` → 429).
     - The router pipeline `event_create_rate_limited` allows 10 requests an hour per user.
   - **Report and block stay as they are.** The event page shows «Διοργάνωση» with the host. Anyone
     other than the host can block a person host from there (`/me/blocks`), which hides their events and
     posts both ways.
3. **Member-group events are no longer forced.**
   - The group's admin picks the price, the audience and guest passes like any host.
   - `community_events.audience` is `group | club | open`. The new check is: `open` needs
     `open_to_non_members`, and `group` needs a `channel_id` and is never open.
   - `group_terms/1` and the old check constraint are gone.
   - `EventPolicy.audience/1` reads the open flag first, then the column, then `channel_id`.
   - Only `group` events keep ADR-153 §13's visibility (group members and staff). A group's `club` or
     `open` event is seen like any club or open event, and its card still goes in the group.
   - This replaces ADR-153 §13's "always free, never open, no guest passes".
4. **Co-hosting.**
   - The host asks a business, by its page address (slug), to co-host one event and its later weekly
     occurrences (`POST …/community/events/:id/cohosts`). There are at most 10 co-hosts per event, and
     never for a `group` event or by the host itself.
   - The co-host's owners and admins get a notification (`community_event_cohost_request`) and answer in
     their console (`…/community/cohost-requests/:id/answer`). The host is told the answer
     (`community_event_cohost_answered`).
   - An accepted co-host shows the event on its page's Events tab and posts a card in its gym club's
     announcements. Its feed snapshot keeps the host's `organization_id` and `"cohost" => true`.
   - **Own trial offer.** After the event, an accepted co-host can send its own one-time trial offer to
     the people who came and aren't its members (`…/cohost-requests/:id/trial-offer`). The trial request
     then counts as referred by that event (`Community.event_cohosted_by?`).
   - **Cross-tenant access.** Rows live in `community_event_cohosts`, in the host's tenant with RLS. The
     co-host never gets a loosened policy. It goes only through narrow `SECURITY DEFINER` functions, each
     of which checks the acting user's role in the co-host organisation:
     - `palee_event_cohost_requests` and `palee_respond_event_cohost`;
     - `palee_accepted_event_cohosts` and `palee_event_cohosted_by`;
     - `palee_cohost_trial_offer_facts` and `palee_claim_cohost_trial_offer`;
     - `palee_event_host_kinds`.
     The tenant trigger on this table stamps `organization_id` on INSERT only, so a co-host's definer
     update never moves the row into its own tenant.
5. **The organiser console** (`/events/hosting?org=&tab=&event=`) has three tabs and nothing else from the
   gym console:
   - **Διαχείριση (Manage):** the event list, each event's attendees, check-in, paid-at-the-box, refunds
     (new: `PUT …/attendees/:user_id/refund`), messages, the host invite link and co-hosts. A business also
     sees its co-host requests here (accept, decline, stop co-hosting, own trial offer).
   - **Οικονομικά (Finances):** income, refunds, net and outstanding per event, plus totals per currency
     (`GET …/community/event-finances`).
   - **Αναλυτικά (Analytics):** views, distinct viewers, RSVPs, waitlist, attendance and conversion
     (`GET …/community/event-analytics`).
   - **Privacy-safe view counting.** `POST /api/me/events/:id/views` stores a daily HMAC of
     (event, viewer, day), keyed with `KeyDerivation "event-view"` and truncated to 16 bytes, in
     `community_event_view_marks`. It also counts per day in `community_event_view_days`. Nothing maps
     back to a person, and the host's own views do not count.
   - The console runs in the host's organisation through the usual `/org/<slug>/admin` routes, so all
     authorisation is the ADR-064 capability check (`manage_events`, or `take_payments` for refunds).

## Rationale
- **Reusing the tenant model for «Ως εγώ».** A one-person organisation keeps every existing guarantee: RLS,
  tenant export and purge, the staff event console, payments, notifications and feed snapshots. A
  "personal event" would have needed a parallel, tenant-less path through all of them.
- **Co-hosting as a request plus narrow definer functions.** This keeps the host's tenant the only owner of
  the event's data, while letting a second business show it and act on its own audience.
- **Hashing views.** A daily keyed hash is enough for distinct viewers and conversion without a viewer log.

## Alternatives Considered
- **Events owned by a user, with no organisation.** Every tenant-scoped table, policy and console would
  need a second ownership model. Rejected.
- **Co-hosts as members of the host's tenant.** This would give the co-host's staff access to the host's
  other data. Rejected.
- **Loosening RLS so co-hosts can read cohost rows.** The project rule forbids it, and it is harder to
  audit than definer functions. Rejected.
- **Counting views per user id.** It is a viewer log. Rejected for privacy.

## Consequences
- `provider_kind` gains `organiser`. Places that branch on gym or coach treat organiser as a gym-like
  tenant without a schedule. The organiser plan is the free plan.
- **Refunds** record the amount on the attendee row (`refunded_at`, `refund_cents`) and appear in
  Finances. They do not create Finance credit notes (TD-185).
- **Reporting.** Organiser events are posted as profile posts, which the platform's report review does
  not cover yet. Blocking is the safety tool for now (TD-185).

## Implementation Notes
- **Migration** `20261205100000_event_organisers_and_cohosts`:
  - the `audience` column and its relaxed check;
  - `community_event_cohosts`, with RLS and the INSERT-only tenant trigger;
  - `community_event_view_days` and `community_event_view_marks`, with surrogate ids for export and purge;
  - the definer functions;
  - and the organiser `provider_kind`.
  All new tables are registered in the tenancy audit and purged by the Community `TenantDataPolicy`.
- **Web:**
  - `HostedEventSheet` («Νέο event» on Events, with the host picker);
  - `EventEditorSheet` (`mode`: club, group or self; the audience pills);
  - `HostingConsole` and the `src/app/events/hosting` route;
  - `HostedEventPanel` (the staff event view with an explicit console scope);
  - `CohostsPanel` and `RefundSheet` in `StaffEventPage`.
- New event payload fields (`audience`, `host`, `cohosts`) are required in the API schema but read as
  optional on the web, so older stubs and cached payloads still render.
