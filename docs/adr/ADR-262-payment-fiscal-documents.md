# ADR-262: Every recorded payment issues its fiscal document

Status: Accepted (2026-10-29, v3.0.0)

## Context

Finance records the money a client pays: at the desk
(`ReceiveFinancePayment`, `CreateFinanceReceipt`) and online, when a
payment intent succeeds (`FinanceFulfilment`, ADR-246/248). The fiscal
core (ADR-240–245) issues the legal documents and sends them to the tax
authority (myDATA through the outbox, ADR-243). Until now the two were not
joined: staff had to issue a receipt by hand. In Greece a card payment
must be tied to its legal receipt (ΔΕΔ 1441/2026, POS–ΦΗΜ/myDATA link), and
a missing receipt is a fine per document.

## Decision

* An application use case, `Palee.Application.Fiscal.PaymentDocuments`,
  issues the receipt in the same request that records the money. Finance
  and Fiscal stay unaware of each other; the bridge lives in the
  application layer.
* Only when the business's fiscal identity is complete. Before that the
  payment keeps Finance's own document (`fiscal_document: null`).
* Lines: the invoice's lines with each package's tax category (ADR-244,
  `SaleLines.finance_invoice/4`). A payment of part of an invoice gets one
  line per tax group `{category, exemption reason, rate}` in proportion,
  rounded by largest remainder so the parts add up to the cent
  (`SaleLines.payment_part/3`).
* Payment method mapping: `card_manual` and `card` → `card`, `cash`,
  `bank_transfer`, `online`; anything else → `other`.
* Idempotent per Finance payment: the key `finance-payment:<id>` returns
  the same document on a replay or retry.
* Desk: the payment stays recorded even if issuing fails; the answer
  carries `fiscal_error` (the reason code) so staff see it, and repeating
  the request issues it.
* Online: a failed issue fails fulfilment, so the payments worker retries
  it (the payment record is idempotent per intent). `fulfil` returns
  `fiscal_document_id`.

## Not yet

* Credit notes for refunds and withdrawals: `Fiscal.credit` credits by
  position and quantity; a partial refund needs an amount-based credit
  split by tax group like `payment_part`. Follows in a later ADR.
* Shop orders and revenue streams keep their own documents for now.

## Consequences

* Turning on the fiscal identity makes every later payment produce a
  numbered, journaled document; nothing is issued retroactively.
* The finance answer for a payment gains `fiscal_document` (id, kind,
  series, number, gross, currency, issue date).
