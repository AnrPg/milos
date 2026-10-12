# ADR-097: Package Phase B — Booking Rules, Perks and Facility
Date: 2026-10-12
Status: Accepted

## Context
ADR-096 introduced package types and the entitlement catalog v2 and shipped
Phase A. Phase B fields (booking privileges, rollover, time windows, perks,
facility access and the remaining commercial terms) exist in the catalog but
are pinned to their presets because nothing enforces them yet (TD-048). The
product also lacks the underlying features: waitlists, booking windows,
cancellation cutoffs, guest bookings, freezes, events, locations and open-gym
check-ins.

## Decision
Phase B makes every Phase B catalog field authorable and enforced, and adds the
missing product capabilities, keeping Finance as the owner of the package
contract and ledger and Scheduling as the owner of bookings.

Commercial terms (Finance):
- **Minimum commitment**: assignment stores `commitment_ends_on`; cancelling a
  subscription before it requires an explicit override reason.
- **Joining fee**: the first invoice prefilled for a member's first subscription
  of a package gains a `manual_charge` line for the fee.
- **Validity from first use**: assignment leaves `ends_on` open and the first
  reservation activates the subscription (`activated_on`, `ends_on`).
- **Expiry reminders**: a daily job notifies members `expiry_reminder_days`
  before a one-off subscription ends (`package_expiring`).
- **Freeze days**: `finance_subscription_freezes` records freezes. A freeze
  extends a dated subscription by its length, blocks reservations while active
  (`finance_membership_frozen`) and is limited by the yearly allowance per
  calendar year.
- **Member discount**: invoice lines gain an optional `charge_category`
  (`product`, `personal_training`, `event`, `other`); creating an invoice adds a
  `discount` line for manual charges whose category is in the member's
  discount scope.

Booking rules (Scheduling, with Finance terms read through an Application
service):
- **Credit weighting**: class types gain `credit_cost` (1–10); a booking
  reserves that many units.
- **Events**: class types gain `kind` (`class` or `event`). Booking an event
  uses the `events` channel, `book_events` capability and `event_visits`
  allowance instead of group-class access.
- **Time windows**: bookings outside the package's allowed weekday/time windows
  (in the finance entitlement timezone) are denied
  (`finance_time_window_not_included`).
- **Booking window**: scheduling settings gain `default_booking_window_days`;
  a package may override it. Booking a class that opens later is denied
  (`booking_window_closed`).
- **Cancellation cutoff**: scheduling settings gain
  `default_cancellation_cutoff_hours`; a package may override it. Withdrawing
  inside the cutoff cancels the booking but consumes the visit and records a
  `late_cancel` attendance.
- **No-show waiver**: when waived, a `no_show` attendance releases the visit
  instead of consuming it.
- **Rollover**: unused units of the immediately previous calendar period carry
  over up to `rollover_max` (no chaining).
- **Waitlist**: a full class accepts `waitlisted` bookings ordered by package
  waitlist priority (high first) and then join time. Freed capacity promotes the
  next eligible entry through the normal booking saga and notifies the member
  (`booking_waitlist_promoted`).
- **Guest passes**: a member may book a named guest into a class. The guest
  booking counts toward capacity and consumes the `guest_passes` allowance.

Facility (new `Facility` bounded context):
- **Locations** belong to the organization; scheduled classes and series may
  reference one. A package may restrict bookings and check-ins to locations.
- **Open gym check-ins** are recorded by staff or by the member, consume the
  `open_gym_visits` allowance once per day and respect location scope.

The `open_gym` and `events` modules become available. The wizard shows Open gym
and Events service cards when their modules are enabled.

## Rationale
Every rule is enforced where the owning data lives, and the ledger stays the
single source of usage. Reading package booking terms through an Application
service keeps Scheduling free of Finance schemas. Reusing scheduled classes for
events and the booking saga for waitlist promotion and guests avoids parallel
booking engines.

## Alternatives Considered
A separate events catalog with its own booking flow was rejected: events are
scheduled, capacity-limited sessions like classes.

Charging member discounts automatically on every invoice line was rejected:
without a category the system cannot know what a manual charge represents.

Chained rollover was rejected because balances could grow without bound and
are hard to explain to members.

## Consequences
Bookings gain `waitlisted` status, waitlist and guest columns; class types gain
`credit_cost` and `kind`; subscriptions gain commitment and activation dates;
two notification types are added across the database constraint, enum, push
builder, inbox presentation and locales (TD-023 still applies).

## Implementation Notes
To be completed when Phase B is finished.
