# ADR-260: What members pay online, and failed saved-card charges
Date: 2026-10-29
Status: Accepted

## Context
The approved mockup for online payments (option B) has one card in
Ρυθμίσεις › Πληρωμές: one sentence saying what members pay online with
«Αλλαγή» for exceptions, and a failure policy under «Προχωρημένα»
(3 retries at 1, 3 and 7 days, member told with a link for another card,
grace days, staff told), with charges that need a person in
Οικονομικά › Ουρές. ADR-246/247 had dunning but nobody heard about a
declined card, and nothing let a business keep, say, shop payments at the
desk only.

## Decision
1. **Options on the provider account** (`payment_accounts.options`, a map
   with defaults, so old accounts mean «everything online, everyone told»):
   `purposes` (`packages`, `autopay`, `drop_in`, `shop`,
   `personal_training`, all on by default), `notify_member`,
   `notify_staff`. `Payments.available?/2` answers per purpose; package
   sales map `pt_pack` to `personal_training` and `drop_in`/`trial` to
   `drop_in`, the shop checks `shop`, autopay checks `autopay`. Paying an
   open invoice online stays allowed while the account is active: it is
   money already owed. `PUT /admin/payments/account/options` changes keys
   given and keeps the rest; unknown keys and non-booleans are refused
   field by field.
2. **One home per rule.** The retry schedule stays in `IntentPolicy`
   (1, 3, 7 days) and is not a setting. The grace period is Finance's
   `subscription_grace_days`; the payments card shows and edits that same
   setting rather than keeping a second copy.
3. **Failure notices** through a port `Payments.Ports.Notifier` (adapter
   `Application.Payments.FailureNotices` over Notifications). After every
   declined saved-card charge (not a provider outage), the member gets
   `payment_failed` (category «account», locked) linking to pay with
   another card; when no retry is left, staff with `manage_billing` get
   `payment_needs_attention` (category «staff»). Deduplicated per attempt
   and per recipient; a notification failure never touches the payment.
4. **Ουρές queue.** `GET /admin/payments/attention` lists merchant charges
   declined and waiting for a retry or failed for good, until staff close
   them or the same purpose is paid by a later online payment; invoices
   paid since in any other way (desk, transfer) are left out. Staff can
   send the card link again (`card-link`, at most once a minute), charge
   once more now (`retry-charge`: one attempt, a decline fails it again
   without new retries), or close it (`dismiss`, e.g. paid at the desk;
   it also stops pending retries).

## Consequences
- The member hears about a declined card within the same job that charged
  it, so the grace days are spent fixing the card, not finding out.
- `drop_in` and `personal_training` switches are stored and enforced for
  package sales now; booking-time payment (CP-A3 drop-in at booking) reads
  the same switch when it is built.
- One-button connect (Stripe Connect OAuth, Viva ISV) is a separate step:
  it needs Palee registered as a Stripe Connect platform and a Viva ISV
  partner first.
