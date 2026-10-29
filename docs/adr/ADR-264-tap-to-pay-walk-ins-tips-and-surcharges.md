# ADR-264: Tap to Pay for walk-ins' free sales, tips and card surcharges
Date: 2026-10-29
Status: Accepted

## Context
ADR-249 put Tap to Pay at the desk on the Viva.com Terminal app, with two
limits the product owner lifted on 2026-10-29:

1. **Walk-ins** (someone with no Palee account, or not a member of the
   box) could pay only a shop order. A drop-in, a bottle of water or a
   day pass sold to a walk-in is a **free sale** (`free_sale`), which
   needed a member because Finance documents hang off a membership (only
   the shop stream, ADR-190, may have none).
2. **Tips and surcharges**: when the Terminal app adds a tip or a card
   surcharge, Viva's amount differs from the request and Palee refused it
   (`amount_mismatch`): the money was taken but never recorded.

What Viva documents (read 2026-10-29):

- **Terminal app Sale request** (Android and iOS): `tipAmount` is "the tip
  that will be added on top of the amount"; `skipSurcharge` turns the
  surcharge off for one sale. **Response** (callback): `amount`,
  `tipAmount` ("how much of the amount in cents is considered as tip") and
  `surchargeAmount` ("the surcharge fee applied to a transaction to offset
  the cardholder's transactional costs"), all in cents. Viva's sample:
  `amount=146&tipAmount=23&surchargeAmount=47`.
- **Surcharge**: enabled by Viva per merchant; "automatically calculated
  and added to the transaction total" for business and non-EEA consumer
  cards only (PSD2 forbids surcharging EEA consumer cards), as a
  percentage of the sale amount; the customer may skip it; a refund
  recalculates it proportionally ("Sales Amount €10 | Surcharge €2 |
  Total €12").
- **Retrieve Transaction** (`GET /checkout/v2/transactions/{id}`, the call
  Palee already confirms with): `amount` ("the amount … that corresponds
  to this transaction ID", decimal), `tipAmount` ("the tip amount of the
  transaction, if applicable") and `surchargeAmount` (nullable decimal).
  Since February 2026 `SurchargeAmount` is also in the legacy Transaction
  Retrieval API and the payment webhooks, whose `Amount` is "the total
  funds paid by the customer"; `TipAmount` is in the webhook too.

Greek treatment (research 2026-10-29, to be confirmed with the box's
accountant):

- **Tips** given to staff are not consideration for the supply. Under
  ν. 5162/2024 tips collected by card «καταχωρούνται ευδιάκριτα στα
  βιβλία της επιχείρησης, αποδίδονται στο ακέραιο, δεν επιβαρύνονται με
  ΦΠΑ και δεν αποστέλλονται στο myDATA», and up to €300 a month they are
  free of the employee's income tax (a 2026 bill in consultation raises
  the limit). AADE's guidance: they are booked as pending items
  (εκκρεμείς συναλλαγές) and paid to the staff with payroll; the POS has
  a separate tip entry so that the card amount and the receipt's total do
  not show a turnover difference.
- **A card surcharge** is part of the price the customer pays for the
  sale (it is consideration, and it follows the VAT treatment of the
  supply it is charged on), so it is revenue and must be on the receipt.

Sources:
[Android Sale request](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/android-app/sale/) ·
[iOS Sale request](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/ios-app/sale/) ·
[Surcharge](https://developer.viva.com/apis-for-point-of-sale/surcharge/) ·
[Payment API (Retrieve Transaction)](https://developer.viva.com/apis-for-payments/payment-api/) ·
[Transaction Payment Created webhook](https://developer.viva.com/webhooks-for-payments/transaction-payment-created/) ·
[Release notes 2026](https://developer.viva.com/releasenotes/2026/) ·
[taxheaven: tips under ν. 5162/2024](https://www.taxheaven.gr/circulars/49792/arora-filodwrhmata-tips-lysh-toy-problhmatos-ergodotwn-kai-ergazomenwn) ·
[ieidiseis: AADE on tips paid through the POS](https://www.ieidiseis.gr/oikonomia/99332/pos-dinoyme-sosta-to-filodorima-ston-ergazomeno-anakoinosi-aade/).

## Decision
1. **A walk-in may pay a free sale.** `TerminalPolicy` lets a payment
   with no member be a `shop_order` or a `free_sale`. A walk-in's free
   sale is its own sale: the intent's `purpose_id` is a new id and
   `metadata.walk_in = true`. The description stays required.
2. **Its money is a Finance stream sale with no membership.** On
   fulfilment, `TerminalSale.walk_in/3` (pure, Payments domain, like the
   shop's `RevenueLineage`) builds a Finance invoice with the sale line
   (`manual_charge`, the free sale's charge category; stream `event` for
   an event charge, else `other`) and one `card_terminal` payment, both
   with `source_type = "walk_in_sale"` and `source_id = <intent id>`. The
   new port callback `RevenueStreamStore.record_sale/2`
   (`Finance.record_stream_sale/2`) writes invoice, lines and payment in
   one transaction, **idempotent per payment source** (a retry answers the
   first sale, `replayed: true`), backed by a unique index on live
   payments of `walk_in_sale` / `card_surcharge` sources. Finance now
   allows memberless rows for the `shop`, `event` and `other` streams;
   membership and package money still always name a membership.
3. **Its fiscal document** is issued from that Finance payment exactly as
   ADR-262 issues any payment's (`ReceiveFinancePayment.record_walk_in/3`
   → `PaymentDocuments.issue/4`): a receipt with no buyer, the free-sale
   line in the business's default tax category (its country's standard
   rate, or exempt with the legal mention for a non-VAT-registered
   business), idempotent per Finance payment (`finance-payment:<id>`). A
   refund reverses the stream payment (no refund receipt: there is no
   party) and credits the receipt.
4. **Tips and surcharges are accepted when Viva names them.** The
   terminal gateway reports `tip_cents` and `surcharge_cents` beside
   `amount_cents` (Viva: `tipAmount`, `surchargeAmount` of Retrieve
   Transaction). `TerminalPolicy.split/2` takes them out of what the card
   paid; what is left must be the requested amount exactly, in the
   intent's currency. Then the payment succeeds and the intent keeps
   `amount_cents` (the base) and the new `tip_cents` and
   `surcharge_cents`. **Any other difference still fails**
   (`amount_mismatch`), as does a negative or malformed tip or surcharge.
5. **A tip is the staff's, not revenue.** It is never in a Finance amount
   or on a receipt line, and it is not sent to myDATA: it stays on the
   intent and on the Finance payment's `params` (`tip_cents`), apart from
   the sale, for reconciliation with Viva's settlement and the payroll
   hand-over (the books show it as owed to the staff).
6. **A surcharge is part of the sale's price.** It is revenue on its own
   Finance stream sale (`TerminalSale.surcharge/4`: stream `other`,
   `source_type = "card_surcharge"`, the member's membership when there
   is one), idempotent per intent, and it is printed on the **same
   receipt** as the sale (one card transaction, one receipt), as lines
   that follow the sale's tax groups in proportion
   (`SaleLines.follow_sale/3`), described «Επιβάρυνση κάρτας» (Greek
   businesses) or "Card surcharge". A walk-in's surcharge is a second
   line of the walk-in's own invoice. Shop orders get the Finance row
   only (the shop issues no Palee receipt yet, TD-190).
7. **API**: the terminal payment answer gains `tip_cents` and
   `surcharge_cents`; `user_id` may be empty for a free sale; the
   dev/test `sandbox-complete` takes `tip_cents`, `surcharge_cents` and
   `amount_cents` (to try a mismatch).

## Rationale
- **A stream sale, not a fake membership:** creating a member for a
  stranger would pollute member lists, counts and GDPR exports; ADR-190
  already models memberless money for the shop with a stream and a
  source, so the walk-in reuses it and keeps the revenue lineage
  (Finance total → payment → intent → Viva transaction).
- **Through Finance, not straight to Fiscal:** the receipt stays derived
  from a Finance payment (ADR-262), so refunds, credit notes, reports,
  exports and reconciliation work the same as for every other payment;
  issuing a fiscal document with no Finance row would leave revenue out
  of the books.
- **One transaction in the store** (`record_sale`) instead of two calls:
  a crash between the invoice and the payment would leave an unpaid
  orphan invoice on every retry; idempotency per source makes the worker's
  retries safe without a lookup table.
- **Tip outside revenue:** Greek practice treats card tips as money held
  for employees (no VAT, payroll), and mixing them into the sale would
  over-state VAT and turnover. Keeping them on the payment's params
  keeps the bank settlement reconcilable.
- **Surcharge on the same receipt:** the card transaction has one
  receipt; the surcharge is consideration for the same supply, so it
  takes that supply's VAT rate(s).
- **Trust Viva's named parts only:** an unexplained difference is still
  money Palee cannot account for, so it remains `amount_mismatch` for
  staff, as ADR-249 decided.

## Alternatives Considered
- **Issuing the fiscal receipt directly from the payment intent for
  walk-ins**: no Finance row, so no revenue lineage, no reversal path and
  no place in reports; rejected.
- **A synthetic "walk-in" member per business**: one membership
  collecting strangers' sales; breaks member counts, history and GDPR
  erasure; rejected.
- **Recording the surcharge inside the purpose's Finance payment**: the
  invoice would be over-paid (an invoice's balance limits a desk payment)
  and packages and shop orders would need special cases; rejected for a
  separate, sourced stream sale.
- **Recording the tip as Finance revenue with a 0 % line**: wrong for VAT
  turnover and for income tax of the business; rejected.
- **Passing `skipSurcharge=true` and `tipAmount=0` on every request**:
  the box would lose the option altogether; the decision of the product
  owner is to accept them. A box can still turn both off in Viva.

## Consequences
- Finance's `*_member_or_shop_check` constraints now admit memberless
  `event` and `other` rows; the unique index
  `membership_payments_terminal_source_index` guards walk-in sales and
  surcharges against double recording.
- A member's transaction history shows a surcharge as its own payment.
- Refunds of a terminal payment stay limited to its base amount
  (`refunded_cents <= amount_cents`); Viva recalculates the surcharge of a
  refund proportionally, and Palee's credit note credits the refunded
  amount only. Refunding a surcharge or a tip is not modelled yet.
- Tips are not reported anywhere yet beyond the payment's params: a tip
  report per period and person for payroll is follow-up work (the
  Terminal app does not say which staff member a tip is for). Whether
  the POS–ECR link (Α.1155/2023) wants the tip in the card payment's
  myDATA detail is checked when the provider adapter passes POS details
  (ADR-249).
- The adapter must be tried against Viva's demo account with tips and
  surcharge enabled before the first box (that `amount` is the total and
  `tipAmount` / `surchargeAmount` are its parts, as the docs and the
  webhook's "total funds paid" say).
- Shop orders: the surcharge has no Palee receipt until the shop issues
  receipts through Fiscal (TD-190).

## Implementation Notes
- Migration `20270221000000_terminal_walk_ins_tips_surcharges`:
  `payment_intents.tip_cents` / `surcharge_cents` (≥ 0, default 0), the
  wider member-or-shop checks, and the unique index.
- New: `Payments.Domain.TerminalSale`, `RevenueStreamStore.record_sale/2`
  (Ecto adapter: `insert_invoice/1` shared with `record_invoice/2`),
  `Finance.record_stream_sale/2`, `ReceiveFinancePayment.record_walk_in/3`,
  `SaleLines.follow_sale/3`, `TerminalPolicy.split/2` and
  `walk_in_purposes/0`.
- Changed: `TerminalPolicy.confirm_outcome/4` (reference and age are
  checked before the amount split), `VivaGateway.fetch_payment/2` and
  `SandboxTerminalGateway` (tip and surcharge), `TerminalFulfilment`
  (walk-in sales, surcharge rows, surcharge on the receipt, walk-in
  refunds), `PaymentDocuments` (surcharge lines), Finance payment params
  of `card_terminal` keep `tip_cents` / `surcharge_cents`,
  `TerminalPayments` and the terminal OpenAPI schemas.
