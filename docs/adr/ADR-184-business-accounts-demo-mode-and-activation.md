# ADR-184: Business accounts, demo mode and activation by the Palee team
Date: 2026-10-23
Status: Accepted

## Context
Milestone M3. Until now anyone could open an independent coach's practice
(ADR-170) and work with real people from minute one, and a gym only existed
when a vendor provisioned it. We want gyms, boxes and freelance coaches to
sign themselves up, try everything with believable data, and go live only
once the Palee team has spoken to them. While they wait they must be
invisible: no public page, nothing in Γύρω μου or search, no real members,
staff, bookings, payments or messages. Organisers (ADR-185) host events, not
businesses, and are not part of this.

## Decision
1. **Activation is explicit on the organization.** `organizations` gains
   `activation` (`demo` | `active`, default `active`), `demo_started_at`,
   `activated_at` and `activated_by_id`. A check constraint allows `demo`
   only for `provider_kind` gym | coach. A trigger
   (`organizations_activation_guard`) refuses a change of `activation` by an
   acting user who is not a vendor, unless the change comes from the
   activation definer function. Existing organizations are backfilled
   `active` by the column default.
2. **One domain policy decides what goes live.**
   `Organizations.Domain.GoLivePolicy.check(org, action, facts)` answers
   `:ok` or `{:error, :business_not_activated}`. An organization is *gated*
   while it is gym/coach and `demo`. The actions, and the commands that ask:
   - `:invite_people`: `IssueInvitation`, enabling the join link
     (`UpdateJoinLink`), community event invitations.
   - `:join`: `InspectJoinLink`, `JoinByLink`, `InspectInvitation`,
     `RedeemInvitation`. Outsiders get the existing unavailable/invalid errors,
     so a demo business stays invisible. Only its own staff are told why.
   - `:grant_staff_role`: `ChangeMembershipRoles`. A staff role may still go
     to the acting account or to a mock person.
   - `:publish_profile`: `PublishBoxPublicProfile`.
   - `:take_booking`: `SubmitBooking`, `SubmitGuestBooking`, `BookAppointment`
     and event RSVPs, unless the booker is the business's own staff or a mock
     person.
   - `:take_payment`: `RecordFinancePayment`, `CreateFinanceInvoice` and
     `CreateFinanceReceipt`, unless the payer is a mock person.
   - `:send_outside`: corporate invoice email delivery. Notifications are
     handled at their single write point (below).

   `Application.GoLive` computes the facts (staff? mock person?) only for a
   gated organization, so active businesses pay nothing extra. Owners whose
   only businesses are demo businesses cannot create more gyms
   (`business_not_activated`).
3. **Discovery is filtered in SQL.** The definer functions behind the public
   box page and listing, referral invites and Γύρω μου
   (`palee_public_box_by_slug`, `palee_public_boxes`, `palee_referral_invite`,
   `palee_around_host_places`, `palee_around_match_events`) add
   `o.activation = 'active'`. Trials go through the public box lookup and are
   covered by it.
4. **Notifications.** `CreateNotification`, the one place an in-app
   notification (and so its push) is written, asks the definer
   `palee_notification_suppressed(org, user)`. It is true for a mock person,
   or for a demo organization notifying anyone who is not its active staff.
   A suppressed notification is skipped like a duplicate. A demo
   organization's cron jobs still run; what they would send outside is
   suppressed.
5. **One stable error.** `403 {code: "business_not_activated"}`. The web shows
   it as one friendly notice, «Ενεργοποίηση από την ομάδα Palee», with a
   button that files the activation request.
6. **Sign-up.** `/register/business` creates the account (the normal
   sign-up) and then calls `POST /api/business-accounts` (gym | coach). It
   creates the demo organization with the tenant defaults (ADR-133; a coach
   gets the «Team» club and owner+coach roles, ADR-170) and files an
   `activation` request, all in one transaction. The call is accepted only
   within 30 minutes of registering. An older account files a *conversion
   request* instead from Εγώ › Ρυθμίσεις (`/api/me/business-requests`). The
   existing coach self-serve endpoint now opens a demo practice.
   Vendor-provisioned organizations stay active, because the vendor already
   vetted them.
7. **Requests and the vendor queue.** `business_requests` (kind conversion |
   activation, status pending | approved | declined | cancelled | completed,
   one pending request per account and kind). `/platform/business-accounts`
   lists pending requests and the demo businesses with their owners and live
   link. Approving a conversion opens the demo business for the requester
   and queues its activation request. Approving an activation request issues
   the link. That request stays pending and is completed when the link is
   redeemed. Declining closes either kind with an optional note.
8. **Activation links.** A vendor issues a link for one account (by id,
   nickname, or by default the first owner) with the role it grants (owner |
   admin) and a lifetime (one hour to 30 days, default 7). Only a SHA-256
   digest is stored, and an organization has one live link at a time.
   Opening `/activate-business?token=…` while signed in as that account
   shows what will happen. Confirming it runs, in one transaction:
   wipe the demo data, call `palee_activate_business` (validates the link
   for `app.user_id`, sets the organization active, spends the link,
   completes the request, restarts the trial), then grant the roles. The
   grant merges with the roles already held and adds `coach` in a coach
   practice. Any other account gets `invalid_activation_link`.
9. **Demo data is ordinary tracked rows.** `Application.DemoSeeders` is a
   registry of per-section seeders (`members`, `workouts`, `schedule`,
   `finance`). Each declares its `requires` and its `sources` (tables).
   `DemoData.seed(context, section | "all")` runs the plan (requirements
   first, each section once) and records every row in `demo_records`
   (organization, section, source, record id). A seeder may only write
   tables the wipe knows how to delete, and both a registry test and a
   runtime check enforce it. The seeders go through the normal commands,
   such as `Workouts.create_workout`, `Scheduling.create_slot`, approved
   bookings and finance packages, invoices and cash payments, so the
   screens show real shapes.
10. **Mock people are not accounts anyone can use.** They are registered with
    a random unusable password, an `@demo.palee.invalid` email and a
    `<Name>_demo_<hex>` nickname, and are added as members without
    membership events. They never get notifications (rule 4) and are deleted
    with `Identity.delete_tenant_scoped_user` on wipe.
11. **The floating demo button.** On every `/admin` screen of a gated
    business: one floating button. Its popover fills *this* screen's section
    (Members, Schedule, Finance, Workouts, otherwise everything), removes the
    demo data, and asks for activation. Coaches keep the coach layout. The
    gate is the same there because it lives in the commands.
12. **Activation keeps the owner's configuration.** Only rows recorded in
    `demo_records` are removed: mock people, then the seeded rows newest
    first. Everything the owner set up themselves stays: settings, branding,
    class types, packages, the public profile draft. There is no "start
    clean" option.
13. **Subscription (ADR-170).** The subscription is created at business
    creation as before. On activation, a subscription still `trialing`
    restarts its trial from the activation day, because the demo days are
    not trial days. A plan without a trial is left untouched.

## Rationale
- One policy module plus SQL filtering means a new "go live" command has one
  obvious place to ask. Discovery cannot leak even through a query that
  forgets to ask, because the definer functions are the only way in.
- Explicit columns, a constraint and a trigger make activation an auditable
  platform decision that a tenant session cannot flip.
- Tracked rows, not a separate fake data layer: every screen, report and
  permission works on the demo data unchanged, and the wipe is precise.
- Suppressing notifications at their single write point covers every
  existing and future notification type, crons included.

## Alternatives Considered
- **A `demo` flag per row or a shadow schema.** Rejected because every query
  would need to know about it.
- **Client-side mock data.** Rejected: the screens and the server rules would
  diverge, and nothing could be booked, paid or reported.
- **Wiping all tenant data on activation.** Rejected: it is irreversible,
  would delete the owner's real setup work, and can fail on foreign keys.
- **Activation by a vendor button alone.** Rejected: the link ties
  activation to the right account and role and records who issued it.
- **Gating every Γύρω μου or search query in Elixir.** Rejected: the SQL
  definers already are the single entry points.

## Consequences
- Every new command that reaches real people must call `GoLive` (or
  `Organizations.go_live/3`). Tests create active organizations by default.
  `TestFixtures.activate_business!/1` lifts the gate in tests that start from
  a self-serve business.
- A seeder that writes a new table must add it to the store's deletable
  sources, or seeding fails with `demo_source_not_deletable`.
- Mock people are real `users` rows while a business is in demo mode. They
  can appear in global user search (TD-184).

## Implementation Notes
- Migration `20261206100000_business_activation`: columns, constraint,
  trigger, `business_activation_links`, `business_requests` (vendor/system
  write, requester read and cancel), `demo_records` (tenant RLS), the
  definer functions, and the filtered discovery functions. Down restores
  them.
- New tables are classified in `Tenancy.Audit`: `demo_records` is tenant;
  links and requests are platform-administered. They are also listed in the
  tenant-data policy. The store facade
  `BusinessAccounts.BusinessAccountStore` runs through `RepoContext.run` and
  is registered in `mix palee.architecture`.
- Memberships carry `organization.activation`, so the web knows when to show
  the button without another request.
- The schedule seeder links one of the demo workouts to each class, because
  a class without a WOD is a draft nobody can book (ADR-176). So `schedule`
  requires `members` and `workouts`.
