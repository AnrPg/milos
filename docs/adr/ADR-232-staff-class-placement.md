# ADR-232: Staff book or move a member into a class from the member's profile
Date: 2026-10-28
Status: Accepted

## Context
A member's console profile has a «Μετακίνηση σε τμήμα» action: staff book the member into a class, or move one of their upcoming bookings to another class (a phone call, the front desk). ANR asked what it does; reading it showed:

- A move withdrew the old booking as if the member had cancelled. Inside the package's cancellation cutoff that consumed the visit (ADR-097) while the new booking took another one: one move, two visits.
- The new booking was written first, so a member with one visit left could not be moved at all, and the two steps were not one transaction: a failed withdrawal left two bookings.
- The dialog listed every class of the next 30 days on the browser's clock (not the box's, ADR-179), including draft classes and classes the package does not cover; staff only learned why after pressing the button.
- Its labels mixed «Τμήμα», «Μάθημα» and «τάξη»; the canonical term is «Τμήμα» (ontology, ADR-230).

## Decision
1. **A move is one transaction, never a late cancellation.** `PlaceMemberInClass` withdraws the old booking first and returns its visit (`WithdrawBooking.write/4` with `late_cancellation: false`), then writes the new booking (`SubmitBooking.write/4`), both inside `Scheduling.transaction/2`. If the new booking is refused, nothing changes. Notifications, realtime updates, the waitlist promotion of the freed place and analytics run only after the commit (`announce/…`). The cancellation event says `by: :staff`.
2. **Staff placement is approved at once and ignores the member's booking window.** Every other booking rule still applies: the class is open (not cancelled or paused), published, not started, has a free place, the member is not already on it, and the member's package covers it with a visit left.
3. **The server lists the choices.** `GET /admin/users/:id/class-placement` (same capabilities as placing) answers the member's movable bookings (pending or approved, member kind), the upcoming classes of the staff member's branches for 30 days (cancelled ones left out), each with `blocked_reason` (the booking error code, or null), and the box's time zone. The package is checked with the new `Finance.check_entitlements/3`, the same decision `reserve_entitlement` takes, without writing anything (one evaluation per distinct request and gym day).
4. **The dialog** («Κράτηση ή μετακίνηση») shows times on the box's clock, disables a class with its reason in staff words, and lets a move take a class refused only for `finance_allowance_exhausted`, since the move returns the old visit first. A refused placement says why inside the dialog (ADR-214).

## Rationale
The member did not cancel, so charging a cancellation is wrong; and releasing before reserving is the only order in which a member with one visit can be moved. One transaction keeps the two writes all-or-nothing without a compensation step. Listing on the server keeps one source of truth for the rules.

## Alternatives Considered
- Keep "new booking first, then withdraw" and only skip the late charge: still cannot move a member with one visit, still not atomic.
- Compute reasons in the browser from the schedule: duplicates the booking and package rules, and the browser cannot see the package.
- Hide blocked classes: staff would not know why a class they expect is missing.

## Consequences
- `SubmitBooking` and `WithdrawBooking` are split into `write` and `announce`; their public `call` behaviour is unchanged.
- The finance store's reservation decision is now a pure `authorize_reservation/2` shared by `reserve_entitlement` and `check_entitlements`.

## Implementation Notes
- Booking moved by staff is announced to the member as an approved booking (`booking_resolved`), as before.
