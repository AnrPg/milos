# ADR-222: Record money received at the desk, with the document the billing setup calls for
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28): "there is no way to record a payment, that I as a business
received money and issue either receipt or invoice depending on what was
setup. Not even in ledger."

What existed:
- `POST /finance/members/:id/payments` records a payment row only. The member
  finance panel (opened by the client's name in the ledger) showed it as a
  form with no payment method, so every payment was stored as cash, and in
  invoice mode it left no document unless staff first made and issued an
  invoice by hand.
- `POST /finance/members/:id/receipts` (receipt mode) issued a paid receipt,
  but the panel always sent `cash` and generated a new idempotency key on
  every press, so a double press recorded the money twice.
- Which document to issue was decided by the screen (`document_mode` read in
  the browser), not by the server.
- Nothing on the ledger row itself led to any of this.

## Decision
1. **One command, `ReceiveFinancePayment`** (`POST
   /admin/finance/members/:id/payments/receive`, capability `take_payments`,
   so front desk can use it). Body: `amount_cents`, `payment_method`
   (`cash`, `card_manual`, `bank_transfer`, `other`), `idempotency_key`
   (required), and either `finance_invoice_id`, or
   `membership_package_subscription_id`, or `description` (+ optional
   `charge_category`), plus `paid_on` and `notes`.
2. **The server picks the document** from `finance_settings.document_mode`
   (`Finance.Domain.ReceivedPayment.document/2`, pure):
   - an open invoice given → the payment goes against it (partly or in full);
   - otherwise `receipt` mode → a paid receipt;
   - otherwise `invoice` mode → a paid invoice (`document_kind: "invoice"`),
     issued and due on the payment day.
   Receipts and paid invoices share `create_paid_document/3` in the store;
   `create_receipt` now goes through it too.
3. **Idempotent.** The membership row is locked; a payment with the same
   `params.idempotency_key` on that membership answers the first result with
   `replayed: true` (HTTP 200 instead of 201) and announces nothing again.
   The web form keeps one key per payment being entered.
4. **Analytics and domain events** stay the ones payments already use:
   `payment_recorded` (with `document_type`, `reference`, method) and
   `:membership_payment_recorded`.
5. **Web.** «Καταγραφή πληρωμής» (`ReceivePaymentDialog`) opens from a
   «+ Πληρωμή» button on every ledger row (`?receive=<user id>`, deep-
   linkable) and from the member finance panel, replacing its two older
   forms. «Για» lists open invoices (oldest first, amount = balance), active
   πακέτα συνδρομής (amount = price) and «Κάτι άλλο» (description + charge
   category). Method is a choice of four, the date defaults to today on the
   server (gym clock), and a line says which document will be issued. After
   saving: receipt → «Λήψη απόδειξης (PDF)»; invoice → attach the official
   invoice file from the box's invoicing provider. Errors follow ADR-214.

## Rationale
- The billing setup is a business rule; deciding it in the browser let two
  screens disagree and made the API unable to guarantee the document.
- A Palee-generated "invoice" PDF is not a legal tax invoice in Greece
  (myDATA/certified providers issue those), so invoice mode records the paid
  invoice and lets staff attach the real file, as the invoices list already
  does. Receipt mode keeps its generated receipt PDF.
- The existing `record_payment` / `create_receipt` endpoints stay for
  other callers (full finance profile page, imports), unchanged in behaviour.

## Alternatives Considered
- **Fix the panel forms only** (add a method field): still two forms, still
  the browser picking the document, still no entry point on the ledger.
- **A unique database index on the idempotency key**: the membership row lock
  already serialises retries for one member, and keys are per membership; an
  index would need a migration of a JSON expression for no extra guarantee.

## Consequences
- Payments recorded at the desk now carry their real method, which the
  accounting export and reconciliation already read.
- In invoice mode a desk payment without an open invoice creates a paid
  invoice; staff no longer create, issue and settle it in three steps.
- A first invoice for a package with a joining fee includes the fee line
  (`maybe_prefill_invoice_from_subscription`), so a payment of only the
  package price leaves the fee due, shown as «Οφείλονται ακόμη …».

## Implementation Notes
- Floating layers (ui/Popover) became a tree in the same change set's bug
  fix (the ledger «Ανάθεση» menu closed on picking a package); the dialog's
  Selects rely on it.
