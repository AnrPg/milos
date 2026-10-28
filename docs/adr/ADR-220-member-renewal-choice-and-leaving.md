# ADR-220: The member chooses renewal, and can leave the box
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28) asked two things:
- Payment reminders go out every `payment_reminder_interval_days` while a box
  member has an open balance. What if they simply decided not to continue?
- The package editor's «Αυτόματη ανανέωση» was a package setting. Shouldn't
  renewal be the member's own choice?

What the code did: `terms.auto_renew` only allowed staff to issue a renewal
invoice and made the member see «Ανανεώνεται στις …»; no job renewed anything,
and its hint ("when off, the membership ends after one billing period") was
wrong. A member had no way to say they were leaving, so reminders about the
next period's invoice kept coming. Staff could set the membership status to
`cancelled`, but invoices stayed open and reminded. The profile also offered an
«inactive» status that the API rejects.

ANR's rule on debt (2026-10-28 20:39 UTC): only future or not-yet-begun
packages are cancelled. Money owed for a package already used stays owed
until paid, and keeps showing in every screen and figure.

## Decision
1. **The package allows, the member chooses.** `terms.auto_renew` now reads
   «Επιτρέπει αυτόματη ανανέωση». Each subscription carries the member's
   `auto_renew` (default on). Only an active, recurring subscription of a
   package that allows renewal, held by the member themselves (not an add-on,
   which follows its base, nor a company seat) has the choice
   (`MemberRenewal.choice_allowed?/1`).
2. **Turning renewal off never takes a paid period away.** The subscription
   gets its last day (`MemberRenewal.last_day/3`): the end of the billing
   period today falls in (counted from the start in whole periods), a later
   period already paid for, or the end of a minimum commitment, whichever is
   latest. It then ends through the usual expiry, grace and access-ended flow.
   While off, `generate_renewal_invoice` refuses (`renewal_turned_off`), and
   unpaid invoices of that subscription for periods after the last day are
   voided. Turning it back on before the last day clears the date
   (`ends_on_from_renewal_stop`) and its expiry notices.
3. **Leaving the box.** `POST /api/org/:slug/me/membership/leave` (member) or
   `POST /admin/finance/members/:id/leave` (staff, `manage_billing`):
   renewal stops on every running package, the membership gets `leaving_on`,
   `left_at`, `left_by`, `leave_reason`, and `expires_on` no later than that
   day. The member's last day is the latest last day of the packages that
   have begun; staff may pick today or a later day (never a past day), and a
   day inside a minimum commitment needs an override reason, like cancelling
   (ADR-097). Staff picking today also set the membership `cancelled`.
4. **Only what lies after the last day is cancelled.** Packages that would
   start after it are cancelled; unpaid invoices nothing was paid or credited
   on, for a service period that begins after it or for such a package, are
   voided. Everything else stays owed, keeps its payment reminders and stays
   in every report. There is no "write off" in this flow.
5. **Changing one's mind.** `DELETE …/leave`: the member until their last day
   passes, staff at any time. Packages stopped by the leave (same
   `renewal_changed_at` as `left_at`) renew again; voided invoices are not
   restored (staff issue a new renewal). Assigning a new package to a member
   who left clears the leave too.
6. **Staff hear it.** Notification `member_leaving` (staff category, to
   everyone with `manage_billing`) with the last day and reason; leavers get
   no "your subscription ends" or grace notices for the end they chose.
7. **UI.** Εγώ › Πληρωμές › Συνδρομή: an «Αυτόματη ανανέωση» switch on the
   current package and «Αποχώρηση από το box» (or «Τέλος προπονήσεων με αυτόν
   τον coach») with the last day and the debt rule in the confirmation; while
   leaving, the day and «Μένω στο box». Staff: the same switch per package and
   «Σήμανση αποχώρησης» (end of paid period · today · a date) on the box
   member's profile, with «Αναίρεση αποχώρησης».

## Consequences
- Migration `20261226100000`: subscription `auto_renew`,
  `renewal_changed_at/by`, `ends_on_from_renewal_stop`; membership
  `leaving_on`, `left_at`, `left_by`, `leave_reason` with consistency checks;
  notification type `member_leaving`. Both are set only through dedicated
  changesets, never a plain membership or package update.
- `GET /api/me/billing`: subscriptions carry the effective `auto_renew` and
  `can_change_auto_renew`; the membership `leaving_on`, `left_by`,
  `leave_reason`, `leave_preview_on`; `actions.self_service_cancel_auto_renew`
  and `actions.self_service_leave` are real.
- Renewal is still issued by staff; an automatic renewal job, when it comes,
  must honour the member's `auto_renew` and `MemberRenewal.renewal_allowed/2`.
- Staff undoing a leave cannot restore a fixed end date that a chosen day cut
  short; they edit it by hand.
