# ADR-274: Member status from subscription charges, with audited overrides
Date: 2026-10-29
Status: Accepted

## Context
The product owner found a member («tolaras») shown as «Ενεργό» in the ledger
while «Δοκιμαστικό» in his profile, with a 50 € monthly package of which 5 €
was paid, no balance due and nothing in «Εκκρεμότητες». The causes:

* `memberships.status` was typed by staff (default `trial`); nothing worked
  it out. The ledger's status cell cycled through values on every click.
* Assigning a package never created a charge, and no renewal charge was ever
  issued unless someone pressed for one. So nobody owed anything, the
  balance was always «—», and the queues stayed empty.
* «Λήγει» came only from a package's validity; a recurring package showed
  «Χωρίς λήξη» although its period is known.
* «Ποσό» was the last *recorded* payment, pending ones included.

The product owner's rule: the status follows the subscription and payments;
whatever staff change by hand is logged, and hovering it shows who changed
it, when, from what and to what.

## Decision
1. **Charges per period.** Every subscription with a price owes a charge (a
   Finance invoice, not a legal document; the fiscal document is still
   issued with the payment, ADR-262) for each period it runs, due on the
   period's first day. Recurring packages are billed per whole billing
   period counted from `starts_on`; any other package once. The first
   period's charge is `invoice_type = "subscription"` (one per
   subscription, unique index), later ones `renewal` (so renewal figures
   keep their meaning and the existing period index dedupes them).
   `membership_package_subscriptions.charges_from` is the first period
   Palee bills: the start for a new assignment, the next period for an
   import or the TD-017 backfill, nil for free packages and corporate seats.
   Assignment issues the first charge in the same transaction; the hourly
   `SubscriptionChargesJob` issues every begun period, under the
   membership lock, and only while renewal is open (ADR-220: auto-renew on,
   not leaving before the period). Money recorded for the subscription
   without a charge (a desk receipt, an online purchase) counts against the
   period it pays for; an online purchase skips the first charge.
2. **Worked-out status** (`MemberStatus`). `memberships.status` stays the
   lifecycle every access rule reads (`active`, `trial`, `comped`,
   `expiring`, `paused`, `expired`, `cancelled`), now derived;
   `memberships.status_shown` is what staff see, with money folded in
   (product owner's choice «Α»): cancelled › paused › expired › overdue ›
   unpaid › leaving › expiring › trial/comped › active, or `no_package`.
   `unpaid` = a charge fell due within the box's grace days, `overdue` = the
   entitlement is blocked for an overdue invoice. Both are recomputed
   wherever the entitlement snapshot is (every payment, invoice, package,
   freeze, leave) and daily.
3. **Overrides** (`finance_value_overrides`). Staff with `manage_billing`
   may set the status or a subscription's last day by hand. Each row keeps
   who, when, the automatic value it replaced, the value and an optional
   reason; rows are never deleted. One is in force per value. A status
   override ends by itself when its automatic value changes (`lapsed`,
   product owner agreed), a date override when reset. Endpoints:
   `PUT|DELETE /admin/finance/members/:id/overrides/:field`,
   `GET /admin/finance/members/:id/overrides`; `PATCH …/members/:id` with a
   `status` records an override.
4. **Screens.** The ledger shows the status pill and «Λήγει» (period end,
   «ανανεώνεται» while it renews); a value set by hand carries a small dot in
   its corner (no edit icon, product owner) whose hover/tap card shows who,
   when, from → to, reason and «Επαναφορά στο αυτόματο». «Τελευταία πληρωμή»
   is the last *paid* amount · day. «Εκκρεμότητες» opens on «Οφειλές»: one
   row per person, oldest debt first, with «+ Πληρωμή».

## Rationale
Deriving the status from facts makes the ledger, the profile and the queues
agree by construction. Charging per period is the only way debt can exist
to be shown. Keeping `status` as the lifecycle and adding `status_shown`
means access rules, reports and the expiry queue keep working unchanged.

## Alternatives Considered
* Status and payment shown separately («Β»): rejected by the product owner;
  a member who owes would still read green «Ενεργό».
* Overrides that stay until reset: an exception for one month would hide the
  next month's debt.
* Storing the period end in `ends_on`: would end recurring subscriptions.

## Consequences
* After the upgrade every running priced subscription is billed from the
  start of its current period (migration 20270313000000 sets
  `charges_from`), so members who never paid appear at once.
* Freezes do not shift billing periods of open-ended recurring
  subscriptions yet (follow-up).
* Autopay (ADR-260) now finds the renewal charges it was designed to pay.
