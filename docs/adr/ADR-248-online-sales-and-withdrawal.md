# ADR-248: Selling packages and shop orders online, booking after payment, 14-day withdrawal
Date: 2026-10-29
Status: Accepted

## Context
Phase 0 asks for paying at booking (CP-A3) and a sales page (CP-A4): a
visitor or member picks a package on the box's page, pays, and can book the
class they wanted in the same step. Online sales to consumers in the EU,
EEA and UK are distance contracts with a 14-day right of withdrawal (Consumer
Rights Directive 2011/83/EU art. 9, 14(3), 16(a); UK Consumer Contracts
Regulations 2013). Online payments exist (ADR-246/247); the shop had only a
mock provider (ADR-190).

## Decision
1. **Packages sold online.** Staff mark a package `sold_online`. The public
   box page lists those packages (`GET /api/public/boxes/:slug/packages`),
   with whether the box takes online payments and the withdrawal days.
2. **Buying.** `POST /me/packages/:id/buy` opens a provider checkout
   (purpose `membership_package`, price from the package). Nothing is
   assigned before the money is confirmed. Fulfilment creates the membership
   on a first purchase, then assigns the package and records the online
   payment with its receipt or invoice **in one Finance transaction**
   (`receive_payment` with `purchase_package_id`), so a retried fulfilment
   never assigns the package twice (idempotent per payment).
3. **Booking after payment.** `book_slot_id` is kept in the intent's
   `metadata`; once paid, the class is booked through the normal booking
   rules. A refused booking (full, closed) never undoes the purchase: the
   member keeps the package.
4. **Withdrawal.** Where it applies (the business's fiscal country is in the
   EU, EEA or UK; unknown country counts as yes), buying requires the
   member's express request to start now (`start_now`, text versioned and
   hashed in `metadata.withdrawal`). Within 14 days, `POST
   /me/payments/:id/withdraw` refunds the price less the part provided,
   in proportion (the larger of days of the period and visits of a
   fixed-visit package), through the provider, records the Finance reversal
   and cancels the package. The wording is a draft for legal review.
5. **Shop.** An online order placed without a token is paid with
   `POST /me/shop/orders/:id/pay-online` (purpose `shop_order`); fulfilment
   settles the order like a capture (`Checkout.settle_online`, idempotent).
   The basket shows online payment as available when the box's provider
   account is active. Refunds of shop orders stay in the shop's refund flow.

## Consequences
- Selling online needs no new Finance concepts: the same receipt or invoice
  as a desk sale, with `payment_method: "online"` and provider references.
- An order cancelled by the hold sweep while its payer is on the provider's
  page fails fulfilment after its retries and shows for staff to refund.
- The member app's purchase and withdrawal screens follow the approved
  mockups.
