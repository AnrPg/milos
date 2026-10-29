# ADR-246: Online payments through the business's own provider account
Date: 2026-10-29
Status: Accepted

## Context
Members must be able to pay invoices online (Phase 0 of
docs/plans/competitive-parity-and-beyond.md, CP-A1). Palee must not hold
anyone's money (no payment-institution licence), must stay out of card-data
scope, and must work for Greek boxes (Viva is the local default) and the
other MVP markets (Stripe). Providers are slow or down at times, webhooks are
lost or forged, and some calls (Viva recurring charges and refunds) have no
idempotency key, so a resend after a timeout can charge twice.

## Decision
1. **Own account, redirect only.** Each business connects its own provider
   account (`payment_accounts`, one per business; credentials encrypted with
   `EncryptedBinary`, written by staff, never returned, logged or exported).
   The payer enters card details only on the provider's page (PCI DSS
   SAQ A); Palee keeps the provider's references, brand, last 4 digits and a
   reusable token. Providers: `viva` (Smart Checkout + legacy recurring API),
   `stripe` (Checkout Sessions + PaymentIntents, pinned API version) and
   `sandbox` (signed fake provider, enabled only by `:payments_sandbox` in dev
   and test). A gateway port (`Payments.Ports.Gateway`) hides the provider;
   the gateway map lives in config.
2. **Intents.** `payment_intents` hold every payment: `payer` checkouts
   (`awaiting_payer` → `succeeded | failed | cancelled | expired`, 1 h TTL)
   and `merchant` charges of a saved card (`scheduled` → `processing?` →
   `succeeded | failed`). A client idempotency key is unique per business.
   Amounts are integer cents, 1 cent to 100 000, in EUR, GBP, USD or CHF.
3. **Provider calls outside transactions, with a lease.** A worker claims
   due intents (`claimed_at`, `FOR UPDATE SKIP LOCKED`, 5 min lease), calls the
   provider, then writes the outcome. Payer checkouts are polled after 2, 5,
   15, 30 and 60 minutes when no webhook came, until one last look after
   expiry.
4. **Webhooks are hints.** Each account has its own URL
   (`/api/webhooks/payments/<org>/<account>`); events are deduplicated by
   `(account, event id)` in `payment_webhook_events`; Stripe signatures are
   checked on the raw body with a 5-minute tolerance. Whatever an event says,
   the payment is read back from the provider before anything is recorded,
   and a reported amount or currency different from the intent is never
   treated as paid (`amount_mismatch`).
5. **Never resend an uncertain write.** Transport errors that may have
   reached the provider are `{:uncertain, _}`. With Stripe (Idempotency-Key)
   they are retried; with Viva the intent fails with the outcome unknown for
   staff to check, instead of risking a double charge.
6. **Fulfilment port.** A succeeded intent is fulfilled through
   `Payments.Ports.Fulfilment` (retried with backoff, 12 tries). The Finance
   adapter records an `"online"` payment on the invoice
   (`ReceiveFinancePayment.record_online`, idempotent per intent, keeping the
   provider references). Staff can never record `"online"` at the desk.
   The fiscal document for online payments is issued by the Finance → Fiscal
   bridge once V3-M3's sale lines exist; `fiscal_document_id` is reserved.
7. **Refunds** go through the provider with an idempotency key per refund,
   never above what is left, and are recorded as a Finance reversal.
8. **Tenant data.** All five tables have forced RLS and the tenant trigger;
   they are retained for 10 years like Finance, and `credentials`/`token`
   columns are excluded from exports.

## Consequences
- Palee never touches funds or card numbers; each business's provider
  contract, fees and payouts stay theirs.
- The Viva adapter is written from Viva's public documentation and must be
  confirmed against Viva's demo environment before the first live box.
- Shop payments (ADR-190's provider port) should move onto this context.
- Online payments of bookings, packages and shop orders (V3-M5) only need
  new fulfilment purposes.

## Update 2026-10-29: PayPal, Klarna and wallets need no new vendor
Product owner decision (2026-10-29): PayPal and Klarna are offered through
the providers already connected, not through a new vendor.
- **Stripe.** Checkout sessions do not pin `payment_method_types`, so Stripe's
  dynamic payment methods show what the business switched on in its own
  dashboard (cards, Apple Pay, Google Pay, PayPal, Klarna, ...).
  `payment_intent_data[setup_future_usage]=off_session` is sent only when the
  member chose to save the card (`save_method`, `save_card` in the request);
  a one-off payment sends none, so methods that cannot be saved stay on
  offer. Saving a card for autopay works as before (cards only).
- **Klarna on Stripe:** one-off payments only (not offered when the card is
  being saved), B2C only, currencies AUD, CAD, CHF, CZK, DKK, EUR, GBP, NOK,
  NZD, PLN, RON, SEK and USD, and amount limits per country and Klarna
  option (for example France pay in full up to 4,000 EUR, pay later up to
  500 EUR; Germany pay later 0.10 to 10,000 EUR; Belgium pay later 1 to
  1,500 EUR; Greece pay in full up to 4,000 EUR). Stripe hides Klarna by
  itself outside these limits.
- **PayPal on Stripe:** for businesses in the EEA, UK and Switzerland, in
  EUR, GBP, USD, CHF, CZK, DKK, NOK, PLN, SEK and a few more; saving PayPal
  for later charges needs Stripe's approval. Stripe does not offer PayPal to
  Connect platforms using direct charges, so a business connected with the
  one-button Stripe connection (ADR-261, `Stripe-Account` header) will not
  see PayPal; one that pasted its own API keys will.
- **Viva.** Smart Checkout shows the methods the business enabled at Viva
  (PayPal and Klarna included where Viva offers them); `allowRecurring` is
  set only when the card is saved.
- The payments settings screen says this in one line («methodsHint», all 12
  locales). Sources: Stripe Klarna (https://docs.stripe.com/payments/klarna),
  Stripe PayPal (https://docs.stripe.com/payments/paypal), Stripe dynamic
  payment methods (https://docs.stripe.com/payments/payment-methods/dynamic-payment-methods).
