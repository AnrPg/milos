# ADR-243: Reporting fiscal documents to myDATA (outbox, gateways, mapping)
Date: 2026-10-29
Status: Accepted

## Context
Greek businesses must report every receipt, invoice and credit note to AADE's
myDATA and print the MARK (and QR link) the authority returns. There are two
channels: an ERP calling AADE's REST API with the business's own myDATA user
and subscription key, or a certified e-invoicing provider. Card payments at a
terminal must also carry the POS provider's signature (POS–ERP link). The
provider choice for the pilots is still open, and AADE is sometimes slow or
down, so issuing a document must never wait for the authority.

## Decision
1. **Outbox.** Issuing a document whose country profile names an authority
   (`authority: :mydata` for GR) inserts a `pending` row in
   `fiscal_transmissions` in the same transaction (ADR-241). The document
   stays immutable; MARK, UID, authentication code and QR link live on the
   transmission.
2. **States.** `pending` → `sending` (claimed with `FOR UPDATE SKIP LOCKED`,
   one attempt spent) → `accepted` (final) | `rejected` (validation; staff fix
   the cause and retry, or credit and reissue) | `failed` (20 transient errors
   in a row) | back to `pending` with backoff 1 min, 5 min, 15 min, 30 min,
   1 h, 3 h, 6 h, 12 h, then daily. A claim older than 10 minutes is taken
   over. Waiting for something outside the document is a **deferral** that
   costs no attempt: no connection, refused credentials (connection marked
   `invalid` until it is saved again), or a credit note whose original has
   no MARK yet.
3. **Attempt log.** `fiscal_transmission_attempts` is insert-only (the
   ADR-241 trigger) and keeps the XML sent, HTTP status, response (64 KB
   cap), outcome and duration, for audits and support.
4. **Gateways (port `Fiscal.Ports.AuthorityGateway`).** Chosen per
   connection environment (`:fiscal_authority_gateways`):
   `sandbox` → `SandboxAuthorityGateway` (no network, MARKs starting with
   `9000`; pilots before credentials, demos, tests); `test` and
   `production` → `MyDataGateway` (`POST /SendInvoices` with `aade-user-id`
   and `Ocp-Apim-Subscription-Key`; dev and live base URLs overridable in
   config). A provider adapter is one more module behind the same port once
   the provider is chosen.
5. **Connection.** `fiscal_authority_connections`, one per organization and
   authority, with the subscription key encrypted by `DataCipher`
   (ADR-161) and never returned by the API. Saving it journals the change
   (without the key, ADR-242) and makes waiting rows due now.
6. **Mapping (`Fiscal.Domain.MyDataInvoice`, pure).** Receipt → 11.2 ΑΠΥ
   (11.1 ΑΛΠ when a line is goods); invoice → 2.1/2.2/2.3 (1.1/1.2/1.3 for
   goods) by the buyer's country (GR, EU, other); credit note → 11.4 for a
   receipt, 5.1 for an invoice with `correlatedInvoices` = the original's
   MARK. VAT category by rate (24 % → 1, 13 % → 2, 6 % → 3, 17 % → 4,
   9 % → 5, 4 % → 6, 3 % → 9); exempt lines → 7 with the exemption category
   of the VAT-code article named in the reason (`άρθρο 22` → 7, `άρθρο 39`
   → 15 …), article 39 by default for a small business. Payment method:
   cash 3, card and online 7, bank transfer 1, otherwise 5 (on credit).
   Income classification E3_561_003 (retail), E3_561_001 (domestic B2B),
   E3_561_005 (EU), E3_561_006 (other) with category1_3 (services) or
   category1_1 (goods). Names of Greek parties are not sent; amounts are
   positive also on credit notes. Element order follows the XSD.
7. **Schemas in the repo.** The official v2.0.1 XSDs are in
   `apps/api/priv/fiscal/mydata/v2.0.1`; tests validate generated XML with
   `xmllint`. Responses are parsed with entities and external fetches
   disabled.
8. **Workers.** `TransmitFiscalDocumentsJob` (queue `fiscal`) runs right
   after an issue, a retry or a new connection, and every 5 minutes for every
   active organization. A `document_reported` journal entry records each
   MARK.
9. **No cancellation at AADE.** Corrections are credit notes (ADR-241), so
   `CancelInvoice` is not used.

## Consequences
- A Greek pilot gym can issue legal documents from day one in `sandbox`
  and switch to `test`/`production` by saving its myDATA credentials; the
  waiting documents are then sent in order (credit notes after their
  originals).
- Card payments through a terminal need the POS provider's signature
  (`ProvidersSignature`, `tid`, `transactionId`); the mapping accepts them,
  and V3-M4/M6 supply them from Viva.
- The exemption-article table and the classification choices should be
  confirmed by the pilots' accountants; they live in one pure module.
- Documents of other countries create no transmission until their own
  authority adapter exists (Peppol, TSE/RKSV in V3-M7).
