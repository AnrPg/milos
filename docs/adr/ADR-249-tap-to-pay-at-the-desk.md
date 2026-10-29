# ADR-249: Tap to Pay at the desk through the Viva.com Terminal app
Date: 2026-10-29
Status: Accepted

## Context
CP-A2 of docs/plans/v3-pilot-ready.md (V3-M6): staff take a contactless
card on their own phone at the desk, and Palee records the money and the
document. Greek law ties every card payment to its receipt (ΔΕΔ 1441/2026,
fine 10 000 €), so a card payment Palee does not know about is not an
option, and a payment Palee records that never happened is worse.

Viva's «Viva.com Terminal» app turns an iPhone or Android phone into a
card terminal (Tap to Pay / SoftPOS) and accepts payment requests from
another app on the same phone ("app-to-app" / inter-app), answering on a
callback URI. Palee never sees the card.

What Viva documents (read 2026-10-29):

- **Request** (Android: an `ACTION_VIEW` intent; iOS: a URL opened with
  `UIApplication.open`): `vivapayclient://pay/v1?…` with `appId`
  (required), `action=sale` (required), `amount` in cents (required,
  integer > 0), `callback` (required, e.g. `mycallbackscheme://result`),
  `clientTransactionId` (≤ 2048, stored with the transaction and shown as
  the *Merchant Reference*), `customerTrns`, `tipAmount`, `sourceCode`,
  `show_receipt`, `show_transaction_result`, `show_rating`,
  `paymentMethod` (`CardPresent` default), Greek-only installments and
  AADE provider fields (`aadeProviderId`, `aadeProviderSignatureData`,
  `aadeProviderSignature`) or `fiscalisationData`, and `ISV_*` fields
  for ISV partners (`ISV_amount`, `ISV_clientId`, `ISV_clientSecret`,
  `ISV_sourceCode`, `ISV_merchantId`, `ISV_currencyCode`, …). There is
  no currency field outside ISV mode: the terminal charges in the
  merchant's currency. iOS keeps a deprecated `merchantKey`.
- **Response**: the callback URI with `status` (`success` | `fail`),
  `message`, `action`, `clientTransactionId`, `amount`, `tipAmount`,
  `transactionId` (UUID), `orderCode`, `shortOrderCode`, `rrn`,
  `referenceNumber` (STAN), `authorisationCode`, `tid`, `cardType`,
  `accountNumber` (masked 6+4), `verificationMethod`, `transactionDate`,
  `transactionEventId`, `aadeTransactionId`, `sourceCode` and more. A
  failed sale has the same shape; a declined one usually still carries a
  `transactionId`.
- **Android** needs a callback activity with an intent filter on the
  callback scheme; Tap to Pay needs Android 8.1+. **iOS** needs iOS 16.7+;
  Viva's Tap to Pay on iPhone works in AT, BE, BG, HR, CY, CZ, DK, FI, FR,
  DE, GR, HU, IE, IT, LU, MT, PL, PT, RO, ES, SE, NL, NO and the UK. On
  iOS, when the PIN screen shows (above the contactless limit), Apple's
  rules reset the calling app to its idle screen: the callback still
  arrives, but the calling app has lost its state.
- **Confirmation**: `GET /checkout/v2/transactions/{id}` (OAuth) returns a
  transaction's `statusId`, `amount`, `currencyCode`, `merchantTrns`,
  `insDate`, card number; the same call ADR-246 uses for Smart Checkout.
- **ISV mode** lets a platform take a fee per sale with its own
  credentials; it is for Viva ISV partners only, and the ISV secret
  travels inside the intent.

Sources:
[POS APIs](https://developer.viva.com/apis-for-point-of-sale/) ·
[Android app](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/android-app/) ·
[Android Sale request](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/android-app/sale/) ·
[iOS app](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/ios-app/) ·
[iOS Sale request](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/ios-app/sale/) ·
[Verify a payment (Retrieve transaction)](https://developer.viva.com/tutorials/payments/verify-a-payment/) ·
[Webhooks for payments](https://developer.viva.com/webhooks-for-payments).

## Decision
1. **A terminal payment is a payment intent** (ADR-246) with
   `initiation = "terminal"` on the business's own Viva account. It is
   leased, polled, refunded, listed and fulfilled like every other intent.
   Purposes: `finance_invoice` (an open invoice of the member, at most its
   balance), `membership_package` (a πακέτο συνδρομής sold at the desk,
   assigned with its money as in ADR-248), `shop_order` (a shop order
   waiting for payment, for its total; may be a walk-in's) and the new
   `free_sale` (a description and charge category, for a member; the
   intent's `purpose_id` is the member).
2. **Start** (`POST /admin/payments/terminal`, capability `take_payments`
   like ADR-222's desk receive): amount, purpose, member (or none for a
   walk-in shop order), `idempotency_key`. The API answers the intent and
   an **app request**: the provider's URL scheme and parameters, built by
   the server (`appId`, `action=sale`, `amount`, `clientTransactionId`,
   `customerTrns`, `callback`, `show_receipt=false`,
   `show_transaction_result=true`, `paymentMethod=CardPresent`). The
   `clientTransactionId` is the request's **reference**:
   `pt1.<intent id>.<HMAC>` signed with a server key over the business,
   intent, amount and currency, so the phone can come back with nothing
   else (the iOS reset above) and a reference can never be pointed at
   another payment, amount or business. The request is valid for 15
   minutes; Palee never sends ISV credentials to a phone.
3. **Result** (`POST /admin/payments/terminal/result`): the app posts what
   the Terminal app returned (`reference`, `status`, `transaction_id`,
   `message`, …). **The device is never trusted for money**: Palee reads
   the transaction back from Viva (`fetch_payment` of the Viva gateway,
   with the account's credentials) and records it only when Viva says it
   is finished, for the intent's exact amount and currency, with our
   reference as its merchant reference (when Viva returns one), created
   after the request, and not already used by another intent (the
   transaction id becomes the intent's unique `provider_ref`). A device
   failure or cancel without a transaction closes the intent at once
   (nothing to record); with a transaction id it is confirmed like a
   success. A later confirmed success still wins over an earlier device
   failure or cancel: money Viva took is always recorded.
4. **Unconfirmed results stay pending for staff.** When Viva cannot be
   reached or does not know the transaction yet, the intent stays
   `awaiting_payer` with `failure_code = "terminal_unconfirmed"` and the
   payments worker asks again after 30 s, 2, 5, 15, 60 minutes and 6
   hours; then it waits for staff (the existing «retry» of ADR-246, or
   cancel). When no result comes back at all, the worker looks for the
   reference among the day's Viva transactions after the request expired,
   and closes it as `expired` (`terminal_no_result`) after the same
   schedule. A Viva webhook naming our reference (`MerchantTrns`) starts
   the same confirmation.
5. **Idempotent everywhere.** Start: by `idempotency_key` per business.
   Result: a duplicate callback answers the current state; a second
   transaction for a request already paid is refused
   (`terminal_request_used`). Fulfilment: idempotent per intent
   (`payment-intent:<id>` key in Finance, ADR-222).
6. **Money and document.** Fulfilment goes through ADR-222's
   `Finance.receive_payment` with the new Finance method
   **`card_terminal`**, so the box's billing setup picks the document
   (the invoice it settles, a receipt, or a paid invoice), with the
   provider, transaction id and intent kept on the payment. Like
   `online`, staff can never record `card_terminal` by hand. Shop orders
   are settled by the shop (`Checkout.settle_at_terminal`) as the shop's
   desk card method `card_manual` with the provider reference.
7. **Ports.** `Payments.Ports.TerminalGateway` (`app_request`,
   `confirm`, `find_by_reference`) with `VivaTerminalGateway` (reusing
   `VivaGateway.fetch_payment`) and a signed `SandboxTerminalGateway`
   (dev and test only). Providers without a terminal app (Stripe) answer
   `terminal_payments_unavailable`.
8. **The phone side** is a Capacitor plugin `PaleeVivaTerminal`
   (Android intent / iOS URL scheme, callback `palee-terminal://result`,
   last result kept until the web app takes it). Screens wait for the
   approved mockups.

## Rationale
- **Why not trust the callback:** the callback is a URL any app on the
  phone can open, and a staff phone is not a secure element. Confirming
  with Viva is the same rule as ADR-246's webhooks.
- **Why a new method `card_terminal` and not `online`:** a tap at the desk
  is a card-present, face-to-face sale: no distance contract (ADR-248's
  14-day withdrawal does not apply), and Greek reporting needs it as a POS
  payment tied to its terminal transaction (myDATA type 7 with
  `transactionId`/`tid`). It is also not `card_manual`: that is staff's
  word that a card went through on a standalone terminal, while
  `card_terminal` is only ever written after Viva confirmed it, so the
  method itself tells accounting and reconciliation that a provider
  transaction stands behind it.
- **Why the shop keeps `card_manual`:** the shop has its own method
  vocabulary (ADR-190) and already records provider payments with their
  reference in `params`; it moves to `card_terminal` when the shop moves
  onto `Palee.Payments` (ADR-246 consequences).
- **Why a signed reference instead of a stored token:** it survives the
  iOS reset and process death with nothing stored on the phone, and the
  server can check it without a lookup table.

## Alternatives Considered
- **A separate `terminal_payments` table**: a second outbox, worker,
  refund path and admin list for the same thing; rejected.
- **Viva's Cloud Terminal API** (Palee calls Viva, the phone shows the
  request): needs ISV or terminal registration per phone and a network
  round trip per sale; app-to-app works with the box's own Viva app and
  account. Can be added later behind the same port.
- **ISV mode** (Palee's fee per sale): needs Palee to be a Viva ISV
  partner and puts its secret in every intent; out of scope.
- **Walk-in free sales**: Finance documents hang off a membership (only
  the shop stream may have none), so a free sale needs a member for now.

## Consequences
- The Viva adapter is written from Viva's public documentation and must be
  tried against Viva's demo app and account before the first box: in
  particular that `clientTransactionId` comes back as `merchantTrns` from
  the Retrieve Transaction API and in webhooks, and that the legacy
  transactions list by date includes POS transactions.
- Refunds of terminal payments use ADR-246's refund (Viva's cancel by
  transaction id); a refund at the Terminal app itself is not seen by
  Palee until staff record it.
- The fiscal bridge maps `card_terminal` to a card payment with the
  transaction's `tid`/`transactionId` (V3-M3); passing AADE provider
  signature fields to the Terminal app waits for the provider adapter.
- A business on Stripe cannot take Tap to Pay in Palee yet.

## Implementation Notes
- Migration `20270206000000_terminal_payments` widens the intent checks
  (`initiation` `terminal`, purpose `free_sale`) and the Finance method
  checks (`card_terminal`).
- Existing payments files touched (additive): `payments.ex` (worker branch
  for terminal intents, webhook lookup by reference), `viva_gateway.ex`
  (`reference`/`created_at` in `fetch_payment`, `reference` in webhook
  events), `finance_fulfilment.ex` (terminal intents delegate to
  `TerminalFulfilment`).
