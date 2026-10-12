# ADR-098: Package Phase C — New Services and Payment Models
Date: 2026-10-12
Status: Accepted

## Context
ADR-096 and ADR-097 shipped package Phases A and B. The remaining catalog
fields and package types (TD-049) describe services and payment models the
product does not have yet: personal training and assessments, form reviews, a
coach response time, nutrition plans, on-demand
video, advanced progress statistics, add-ons, shared memberships and corporate
memberships. The catalog keeps them at phase `:c`, so the wizard hides them.

Findings that shape the design:
- No v2 package grants the `workout_library` channel, and members have no way
  to browse a library; "self-selected" execution today means doing a scheduled
  class's workout without a booking.
- Unmetered entitlement checks read only the primary stacked subscription, so
  anything bought as a second subscription (an add-on) would be invisible.
- Invoices, payments and the ledger hang off the beneficiary's membership; there
  is no payer distinct from the member and no company account.
- "Coach" is an organization membership role; there is no assigned coach and no
  appointment, nutrition, video or form-review data.
- Members can post `coaching_note` messages without using a touchpoint.

## Decision
Phase C makes every remaining catalog field and package type authorable and
enforced. Finance stays the owner of the package contract, the ledger and all
billing; each new service lives in the context that owns its data.

### Staff roles
No document yet separates what coaches may do from what admins may do, so
coaches hold admin rights: every owner/admin route and membership command
accepts coaches, and a coach ranks as an admin for role grants. Coach-facing
Phase C work (form reviews, the reply queue, nutrition plans, appointments)
lives under `/staff`, which owners, admins and coaches share. A rights-per-role
report will narrow this later (TD-054).

### Entitlement plan
- New channels `personal_training`, `digital_content`, `nutrition`; new
  capabilities `book_pt_sessions`, `book_assessments`, `request_form_reviews`,
  `receive_nutrition_plan`, `watch_on_demand`, `view_advanced_analytics`; new
  allowances `pt_sessions`, `assessments`, `form_reviews`.
- `content.workout_library` is retired: clients never browse the gym's
  workout library, so it is not sellable. The field stays readable for stored
  contracts but is never available and grants nothing.
- The effective entitlement merges every effective subscription (primary,
  stacked one-off packs, add-ons, shared and corporate seats): channels,
  capabilities and scopes are unions; allowances keep their per-subscription
  ledgers and reservation keeps choosing the subscription that can pay.
- Members can no longer send `coaching_note` messages; only staff can.

### Content (Workouts, Execution, Analytics, new `Content` context)
- **Workout vault and repeats (not sold separately)**: clients (members and
  athletes) see their own history. Every completed execution is a dated entry
  with a view of that day's performance and a *Do it again* action. Repeating
  starts a new execution with source `repeat`, referencing the client's own
  earlier execution; it is authorized by ownership and is logged as a separate
  entry on its own date. A *Vault* tab on the client profile lists every
  workout they have completed, with its entries. The gym's library stays
  staff-only, and self-selected starts keep requiring library access.
- **On-demand video**: a `Content` context stores video items (title,
  description, external video URL from YouTube/Vimeo or any HTTPS host,
  duration, tags, published). Hosting video files is out of scope; members with
  `watch_on_demand` list and open published items.
- **Advanced statistics**: clients with `view_advanced_analytics` get a
  progress view of their own training: weekly volume and completion trend,
  score history per scoreable section, attendance consistency and PR timeline.
  Basic stats (landing, PRs, history list) stay available to everyone.

### Coaching (Coaching, Messaging, new `Nutrition` context)
- **Form reviews**: a member submits a video link and a note, optionally tied
  to an exercise or execution. Submitting reserves one `form_reviews` unit; a
  coach's review finalizes it; withdrawing before review releases it. Staff see
  an open-review queue; the member is notified when reviewed.
- **Response time**: `online_coaching.response_sla_hours` is the coach's
  promised reply time. Member messages in a direct thread with staff are
  *awaiting reply* until a staff member answers. Staff get a reply queue with
  due times, and an hourly job notifies staff once when a reply is overdue. The
  member sees the promise; nothing is refunded automatically.
- **Nutrition plan**: a `Nutrition` context stores one current plan per member
  (title, text, optional daily calories and macros, updated by). Staff write
  it; members with `receive_nutrition_plan` read it and are notified when it
  changes.

### Appointments (new `Appointments` context)
- **Decision on open question 4**: coaches publish bookable appointment slots;
  members book themselves; staff can also book on a member's behalf.
- A slot has a coach, start, duration, kind (`pt_session` or `assessment`),
  format (`one_to_one` or `semi_private`), capacity (1, or 2–4 for
  semi-private) and optional location.
- Booking a PT session reserves `pt_sessions`; an assessment reserves
  `assessments`. The package's format must match the slot, a package
  `personal_training.coach_id` restricts the coach, and location scope applies.
  `session_minutes` and `group_size` describe what the member buys and filter
  the slots offered to them.
- Cancelling uses the package/gym cancellation cutoff like classes: a late
  cancellation consumes the session. Attendance (attended / no-show) finalizes;
  a waived no-show releases.
- The `PT pack` type and the `personal_training` module become available.
  Coaches and staff get notifications for new and cancelled appointments.

### Payment models (Finance)
- **Add-on**: an add-on can only be assigned to a member who has an active base
  subscription allowed by `terms.compatible_package_ids` (`all` means any
  active membership-type base). It stores its base subscription, follows the
  base's end date and ends when the base ends or is cancelled. Its benefits are
  merged into the member's entitlement.
- **Shared (decision on open question 2)**: the subscriber is the payer and is
  billed. The payer adds beneficiaries who already have accounts in the gym, up
  to `terms.beneficiaries` people in total (payer included). With
  `quota_sharing = shared` all people draw from one balance; with `per_person`
  each person has the full allowance. A beneficiary may be flagged as a minor
  only when `terms.allow_minor_beneficiaries` is on; minors need an account
  (managed by the guardian) because bookings belong to accounts.
- **Corporate (decision on open question 3)**: a corporate package belongs to a
  corporate client (company name, billing contact). Employees enroll with the
  client's enrollment code, or automatically when `terms.enrollment =
  email_domain` and their account email matches `terms.enrollment_domain`.
  Enrollment creates a seat subscription paid by the company, limited to
  `terms.seats` active seats. The company is invoiced per period through a
  separate corporate invoice: `seat_billing = agreed` bills all seats,
  `used` bills seats active in the period. Members never receive invoices for
  corporate seats.
- The `add_on`, `shared` and `corporate` types and the `digital_content` and
  `corporate_clients` modules become available.

### Corporate invoicing
- A corporate client has payment terms (`payment_terms_days`, default 14) and
  automatic invoicing (`auto_invoice`, default on). A daily job issues each
  period's invoice: `agreed` billing at the start of the period (seats are known
  in advance), `used` billing once the period has ended (seats are only known
  then). Periods before the client was created are never invoiced, and the
  unique period index keeps the job idempotent. Admins can still issue an
  invoice by hand.
- Corporate invoices take their number from the member invoice sequence
  (`INV-000123-CORP-…`), so numbering stays continuous, and carry a due date
  (`issued_on + payment_terms_days`).
- Payments are recorded against an invoice (amount, method, date, reference);
  partial payments are allowed and a mistaken payment can be reversed. The
  invoice is `paid` when its balance reaches zero, and goes back to `issued` or
  `overdue` when a reversal reopens it. Void is only allowed with no payments.
- A daily job marks unpaid invoices past their due date `overdue` and emails the
  client's billing contact a reminder, repeated every
  `payment_reminder_interval_days` (the gym's finance setting) while overdue.
  The billing contact also gets an email when an invoice is issued; emails use
  the gym's default locale.
- The invoice PDF is produced in the browser with the same jsPDF export the app
  already uses for workout documents (DejaVu fonts, so Greek prints correctly);
  emails carry the invoice details in their body rather than an attachment.

## Rationale
Each service is enforced where its data lives and every metered use goes
through the existing ledger, so balances, grants, freezes and reconciliation
keep working unchanged. Merging all effective subscriptions in the read model
is the general fix that add-ons, shared and corporate seats need, and it also
closes the existing gap for stacked packs. External video links avoid building
media hosting and transcoding. A separate corporate invoice keeps member
invoices, payments and dunning untouched.

## Alternatives Considered
- Coach availability rules with free-time booking instead of published slots:
  rejected for now; slots are simpler for coaches and members and cover
  semi-private sessions naturally.
- Payer columns on every invoice for shared and corporate billing: rejected;
  shared payers are already the subscription owner, and a company is not a
  gym member.
- Uploading form-review videos to object storage: rejected for Phase C; links
  avoid large uploads and privacy handling of stored video.
- Automatic SLA credits: rejected; refunds for late replies are a business
  decision left to the gym.

## Consequences
New tables for appointments, nutrition plans, content videos, form reviews,
subscription beneficiaries, corporate clients and corporate invoices; new
subscription columns for add-on base subscriptions and corporate seats. New notification types follow the TD-023 checklist. Remaining limits are
recorded in the technical debt ledger when the phase is complete.

## Implementation Notes
- **Catalog and plan**: `PackageCatalog.implemented_phases/0` is `[:a, :b, :c]`;
  `content.workout_library` has phase `:retired` and is never available.
  `EntitlementPlan` compiles the Phase C channels, capabilities, allowances and
  terms; `serialize/1` stores a `compiled: true` plan that is read back as is (a
  stored plan was previously recompiled from the membership preset), and
  `merge/1` builds the effective entitlement from every effective subscription
  (own, shared as beneficiary, corporate seat, add-ons whose base is still
  effective, minus frozen ones). Each allowance is counted against the first
  subscription that holds it; shared `per_person` quotas count only the
  consuming member's usage. The ledger and its database constraint accept
  `pt_sessions`, `assessments` and `form_reviews`.
- **Staff roles**: `MembershipPolicy.admin_roles/0` is `[:owner, :admin, :coach]`
  and a coach ranks as an admin for role grants (never owner). The router's
  `admin_only`, `organization_admin` and new `staff_only` pipelines and the
  membership commands use it; checks go through
  `TenantAuthorization.roles/1` / `any_role?/2`, which accept a future role set.
- **Workout vault and repeats**: `GET /executions/vault` groups the client's
  completed executions by workout; `source: "repeat"` starts a new execution
  from the client's own completed execution of the same workout
  (`AuthorizeWorkoutExecutionSource`) and needs no entitlement.
- **Content** (migration `20261012200000`): `content_videos` with RLS; admin
  CRUD/publish/archive at `/admin/videos`, members list published items at
  `/me/videos` with `watch_on_demand`. `Analytics.Domain.ProgressStats` builds
  `/me/progress` (12 weekly buckets, consistency and streak, sources, score
  history for sections done more than once) for `view_advanced_analytics`.
- **Coaching** (migration `20261012210000`): `coaching_form_reviews` reserve,
  finalize or release one `form_reviews` unit; `coaching_reply_alerts` record
  one alert per overdue member message; `nutrition_plans` hold one plan per
  member. `CoachingReplyOverdueJob` runs hourly (`23 * * * *`) over member
  messages in direct threads still awaiting a staff reply past the member's
  `response_sla_hours`. Staff routes live under `/staff`; members use
  `/me/form-reviews` and `/me/nutrition-plan`. `SendMessage` turns a member's
  `coaching_note` into a chat message.
- **Appointments** (new context, migration `20261012220000`):
  `appointment_slots` and `appointment_bookings` with RLS and same-organization
  location keys. `BookAppointment` locks the slot, checks capacity, kind,
  format, group size, session length, coach and location scope
  (`AppointmentPolicy`), and reserves through the ledger; cancellation uses the
  booking cutoff (late cancellation finalizes), attendance finalizes and a
  waived no-show releases. Coaches are notified with `appointment_booked` and
  `appointment_cancelled`.
- **Payment models** (migration `20261012230000`): subscriptions gain
  `base_subscription_id` and `corporate_client_id`; new tables
  `finance_subscription_beneficiaries`, `finance_corporate_clients` and
  `finance_corporate_invoices`. `PaymentModelPolicy` holds the rules (add-on
  base choice, beneficiary limits, seat limits, email domain, corporate periods
  and billed seats). Add-ons are not renewed once their base has ended
  (`add_on_base_ended`); corporate seats never get member invoices or joining
  fees. Members enroll through `POST /me/corporate-enrollment` with a code, or
  without one for email-domain plans.
- **API**: every new denial has a stable code in `FallbackController`. The
  OpenAPI spec is now cached once per spec module (`MilosTrainingWeb.ApiSpecCache`)
  because the default cache copied the whole spec into persistent terms for
  every controller action and exhausted the literal area in the full test run.
