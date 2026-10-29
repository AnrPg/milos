# ADR-263: Member payment screens: buying a package, paying an invoice, saved cards, the sales page
Date: 2026-10-29
Status: Accepted

## Context
ADR-246/247/248/256/260 gave the API online payments through the business's own
provider account (Viva, Stripe, or the sandbox gateway): purchase and payment
terms with the legal texts, buying a subscription package or paying an invoice,
saved cards with autopay, withdrawal within 14 days, failed saved-card charges and
`/pay/return`. The member app had no screens for any of it. The mockup
(`docs/product/mockups/palee-ia-mockup.html`) shows them as s4 option B (member,
on the phone) and s5 option C (the box's public sales page).

Building the screens showed four things the API did not give the client:

1. Which provider takes the payment, for the button «Πληρωμή 75,00 € με Viva»
   and the sales page footer.
2. What a package includes, for the sales page cards.
3. A way to say yes to the mockup's «Επόμενες χρεώσεις αυτόματα με αυτή την
   κάρτα» while paying with a new card. Saving the card alone did not set autopay.
4. Whether a visit bought for one booked class has the 14-day withdrawal. It
   does not (Directive 2011/83/EU art. 16(l): leisure services for a specific
   date or period), and the terms text must not offer it.

## Decision
**API (additive, no migration)**
- `provider` (nullable) on `GET /me/invoices/:id/payment-terms`,
  `GET /me/packages/:id/purchase-terms` and `GET /api/public/boxes/:slug/packages`.
  It comes from the new `Payments.provider/1` and is null when online payment is off.
- `services` on each public package. It holds only the booleans and counts
  members compare: group classes, personal training sessions and assessments,
  open gym, events.
- `autopay` (boolean) on `POST /me/packages/:id/buy` and
  `POST /me/invoices/:id/pay`. It counts only together with `save_card` and the
  accepted consent. The intent stores `metadata.autopay`. When the card is saved,
  it gets autopay and every other card of that member at that box loses it
  (`PaymentStore.clear_autopay`). This is the same rule as switching autopay in
  Saved cards.
- `purchase-terms` accepts `book_slot_id`. A `drop_in` or `trial` bought with a
  booked slot is a dated visit: `withdrawal_days` and `start_now_text` are null,
  and buying does not ask for `start_now`.

**Web**
- `/pay/return` (no box slug, AuthGuard). The started checkout is kept on the
  device (`palee.pendingCheckouts`, 24 h), so the page knows the box, what was
  bought and where to go back. Without it, the selected box is asked. With
  `sandbox_checkout=`, it first shows the sandbox provider's page (pay or
  cancel), which calls `POST /me/payments/sandbox/complete`.
- Checkout opens with `openCheckout` (in-app browser, ADR-256). A redirect to
  our own origin, which is the sandbox, is a router push.
- Box › membership card «Ανανέωση» and schedule booking without a package
  (`finance_*` no-package refusal) open the package sheet. The sheet has
  «Πριν πληρώσεις»: when it starts (the API's `start_now_text`) and, for
  recurring packages, renew automatically (the API's `consent_text`) or pay
  myself. Nothing is chosen in advance.
- Εγώ › Πληρωμές: pay an open invoice, Saved cards with the autopay switch and
  remove, and `?payment=<id>`, which is the link in failed-charge notices
  (ADR-260). It shows the declined charge with «Πληρωμή με άλλη κάρτα» and,
  within 14 days, «Υπαναχώρηση».
- `/b/[slug]/packages`: the sales page. It shows the trial first, then three
  packages, the rest under «Όλα», and the provider in the footer. Buying needs a
  Palee account (links to sign in or sign up, then back with `?buy=<id>`) and
  box membership (`/join/<slug>`).
- Store apps hide digital-only packages (ADR-256 `canBuyHere`).

## Rationale
Every legal sentence is the API's text in the payer's language. The screens only
ask the questions and show the answers. Autopay at checkout reuses the rule the
Saved cards switch already follows, so there is never more than one autopay card
per member and box.

## Alternatives Considered
- **Ask for autopay after the return page.** That is a second consent screen
  after the one the payer just accepted, so it was rejected.
- **Keep the pending checkout in the URL.** Providers do not pass our own
  parameters back reliably; Viva only adds `s` and `t`. Kept on the device instead.
- **Create the account inside the sales page's buy dialog.** The `/me` routes
  need tenant membership, and joining has its own consent and approval flow, so
  the dialog links to them instead.

## Consequences
- Not built: the mockup's «Στις 12/11 (μετά τις 14 ημέρες)» start-later option,
  because the API requires `start_now` while withdrawal applies. The trial's
  «Πότε;» slot chips are also not built.
- Copy with no backing in the API was left out: refund for cancelling 2 hours
  ahead, holding the place for 10 minutes, trial price deducted later, «Οι
  περισσότεροι διαλέγουν», the next charge date.
- Renewing reads `GET /api/public/boxes/:slug/packages`, so it needs the box's
  public page to be published.
- A first-time buyer on the sales page goes through sign-up and joining before
  paying.

## Implementation Notes
- The «top three» packages are the first three in the API's order. There is no
  "featured" flag yet.
- Tests: the API tests are in `online_sales_controller_test.exs` and
  `payments_controller_test.exs`. Web: `src/components/payments/*.test.ts(x)`,
  plus `e2e/member-pay.spec.ts` with a mocked API.
