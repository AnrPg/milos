# ADR-291: A box without online payments: «Το θέλω», «Περιμένει πληρωμή» and the shop's pickup pass
Date: 2026-10-31
Status: Accepted (extends ADR-222, ADR-271)

## Context
A box that has not connected an online payment provider (Stripe, Viva) still
showed members buy buttons, a greyed-out «Online» option in the shop cart and
prompts to pay that could never work. ANR asked (2026-10-31, thread "Pay at
the front desk without online payments") that such a box shows no payment
prompts, only sparse «pay at the front desk» messages; packages stay visible
with a button that opens centred instructions; and shop orders get a code to
show at the desk (not packages, where the desk step is already one step).
The mockup (https://claude.ai/artifact/Hn19EkvXzwforKDJzRocFb) settled the
options: **1C** for packages and **2B** for shop orders. ANR added: the desk
sees the person as a link to their account, the request waits as «Περιμένει
πληρωμή» and is kept 14 days (told to the person) before it leaves
«Εκκρεμότητες».

## Decision
- **Package requests are their own table**, `finance_package_requests`
  (tenant RLS), not a subscription status. A request grants no access and owes
  nothing; only «Είσπραξη» at the desk creates the subscription, so an unpaid
  request can never leak into access, renewal charges or debt (ADR-220).
  Statuses: `pending`, `activated`, `cancelled`, `lapsed`. One pending request
  per person and package (partial unique index); asking again returns it.
  The name, price and currency are snapshots taken when asked.
- **14 days.** `PackageRequestPolicy.hold_until/1` is today + 14. The member
  sees «Το κρατάμε 14 ημέρες, έως …» when asking and on the pending card in
  Box; the desk row says «Αφαιρείται σε N ημέρες». An hourly job
  (`LapsePackageRequestsJob`) lapses requests past their date; a new request
  for the same package after that starts a fresh hold.
- **Who can ask.** Box members only (a signed-out person is asked to sign in,
  a non-member to join first). Paid, active packages the box lists at the desk
  (`PackageSale.desk_listed?`: the owner's «Πωλείται online» on, or never
  chosen); add-on, shared and corporate packages need staff and are never
  requestable.
- **«Είσπραξη» is the ADR-222 receive path.** `POST
  /admin/finance/package-requests/:id/collect` (capability `take_payments`)
  records the money, assigns the package starting today and issues the fiscal
  document in one transaction, with the idempotency key
  `package-request:<id>`, then closes the request as `activated` with links to
  the subscription and the payment.
- **The desk sees the person.** `GET /admin/finance/package-requests`
  (`take_payments`, `manage_billing` or `view_finance_reports`, branch-scoped
  like the other queues) returns each request with the person (name, handle,
  avatar). «Εκκρεμότητες» gains the chip «Περιμένουν πληρωμή»; every name in
  every queue row is now a link to `/admin/users/:id`.
- **Visibility.** `PackageSale.visibility/2` returns `no_provider` for a desk
  listed package when no provider is connected (before the owner's off), so
  staff see the badge «Στην υποδοχή». The public Σελίδα πακέτων and the member
  app show those packages with «Το θέλω» and a centred dialog with the steps
  and the box's front desks; renewal opens the same instructions. No buy,
  card or «Online» control is shown.
- **Shop orders (2B).** The cart offers «Online» only when it is available;
  never a disabled option. After placing, a centred dialog shows the QR and the
  6-character pickup code; the order page keeps both and «Αποθήκευση» saves a
  PNG pass (theme colours, QR, code, box, number) drawn on a canvas, so it can
  be shown at the desk with the app closed or offline.

## Consequences
- Activation, receipts and money all go through one existing path; nothing new
  can charge a person.
- The app has no offline cache of pages (no service worker caching), so the
  saved image is the offline way to show a pickup code.
- A staff-created request (`source = staff`) is modelled but not yet used by
  any screen.
