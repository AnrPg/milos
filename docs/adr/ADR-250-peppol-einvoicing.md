# ADR-250: Peppol e-invoicing (UBL 2.1 / BIS Billing 3.0, outbox, access point port)
Date: 2026-10-29
Status: Accepted

## Context
From 1 January 2026 Belgian VAT-registered businesses must exchange B2B
invoices as structured e-invoices over Peppol (law of 6 February 2024;
FPS Finance / BOSA, https://efacture.belgium.be/en/peppol). The format is
Peppol BIS Billing 3.0, a CIUS of EN 16931 in UBL 2.1. Sending goes through
a certified Peppol access point; a box will not run its own. Other
countries (DE receive-mandate, FR 2026–2027) follow, so the network must
be a port and the document mapping must be generic EN 16931.

Like myDATA (ADR-243), issuing a document must never wait for the network,
and an access point that may already have taken a document must never get
it twice.

## Decision
1. **When.** A document is queued for Peppol when its country profile has
   `einvoicing: [:en16931]` (BE), it is an invoice or a credit note of an
   invoice, and the buyer has a Peppol address. The buyer's `peppol_id`
   (`scheme:identifier`) is taken as given or derived: a Belgian VAT number
   or enterprise number becomes `0208:<KBO number>` (mod-97 checked);
   `9925` (BE VAT) is accepted. Invalid input is `invalid_peppol_id` (422).
2. **Format.** `Fiscal.Domain.UblInvoice` (pure) maps an immutable document
   to UBL 2.1 `Invoice` (type 380) or `CreditNote` (381) with
   CustomizationID `urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0`
   and ProfileID `urn:fdc:peppol.eu:2017:poacc:billing:01:1.0`. Choices:
   unit code `C62`; a line whose net amount does not divide by its quantity
   is priced for the whole line with `BaseQuantity` = quantity; BuyerReference
   is the buyer's reference, else the document number; paid methods (cash,
   card, online) carry `PrepaidAmount` = gross, others a `DueDate` and
   "payable on receipt" terms in the document's language; tax categories
   S, Z and E (with exemption reason). `UblWriter` serialises the tree.
3. **Outbox.** `fiscal_einvoice_submissions` (one per document) with states
   `pending` → `sending` (claimed with `FOR UPDATE SKIP LOCKED`, one attempt
   spent) → `submitted` (access point took it; delivery polled at 2 min,
   5 min, 15 min, 30 min, 1 h, 3 h, 6 h, 12 h, then daily three times) →
   `delivered` | `rejected` (refused, or delivery failed) | `failed` (20
   transient errors, or delivery unconfirmed after the last poll) |
   `uncertain`. No connection or refused credentials is a deferral that
   costs no attempt. `fiscal_einvoice_attempts` is insert-only (ADR-241
   trigger) and keeps the UBL sent and the answer, never the key.
4. **Uncertain is never resent automatically.** A timeout or dropped
   connection, a claim older than 10 minutes, or the access point refusing
   a reused idempotency GUID makes the row `uncertain`. Staff check the
   provider's portal; a staff retry of an uncertain row keeps the same
   idempotency GUID so the access point refuses a copy instead of
   delivering it twice. A refused or failed row is retried with a new GUID.
5. **Port and adapters.** `Fiscal.Ports.EInvoiceNetwork` (`submit/2`,
   `status/2`), chosen by the connection's provider: `Sandbox` (local,
   deterministic; recipient `0000000097` fails delivery) and `Storecove`
   (`POST /document_submissions` with `rawDocumentData`, `parseStrategy:
   "ubl"`, routing `eIdentifiers`, and `idempotencyGuid`; delivery read from
   `GET /document_submissions/{guid}/evidence/sending`, 404 = in progress).
   Palee sends the UBL it generated and validated, not a provider JSON.
6. **Webhooks are hints.** Each connection gets a secret URL
   `/api/webhooks/peppol/:organization_id/:token` (token shown once, kept
   only as a SHA-256 hash). A notification only makes the next delivery
   poll due now; the state is always read from the access point.
7. **Journal.** `network_connection_saved` and `document_delivered` are
   journaled (ADR-242).
8. **Endpoints** (staff; reads `view_finance_reports`, writes
   `manage_billing`): `GET/PUT /fiscal/peppol-connection`,
   `GET /fiscal/einvoices`, `GET /fiscal/einvoices/:id`,
   `POST /fiscal/documents/:id/einvoice/retry`; documents show `einvoice`.
9. **Tenant data.** Three tables with forced RLS and the tenant trigger;
   listed in `audit.ex` and the Fiscal `TenantDataPolicy` (export excludes
   `api_key` and `webhook_token_hash`; purge deletes them).

## Rationale
An access point as a service keeps Peppol certification, SMP registration
and AS4 out of Palee; sending Palee's own UBL keeps the document the box
issued byte-for-byte what the buyer gets, and lets Palee validate it. The
outbox and attempt log reuse the ADR-243 shape operators already know.

## Alternatives Considered
- **Provider JSON (Storecove's own invoice model).** Simpler request, but the
  mapping would live at the provider and could not be validated here.
- **Own access point (phase4/Oxalis).** Certification, PKI and 24/7 AS4
  operations are out of proportion for boxes.
- **Resending uncertain rows automatically with the same GUID.** Relies on
  every provider deduplicating; a human check is cheaper than a duplicate
  invoice in the buyer's books.

## Consequences
- Boxes need a Storecove legal entity (with their Peppol id registered) and
  an API key for `test`/`production`; the sandbox needs none.
- Receiving invoices over Peppol is not covered (boxes rarely need it in
  the pilot; Storecove can deliver to email meanwhile).
- The Storecove paths and payload were written from the public docs and an
  older published OpenAPI; they must be confirmed on a sandbox account
  before the first live box (see Implementation Notes).

## Implementation Notes
- Tests validate the UBL against the official OASIS UBL 2.1 XSDs (vendored
  under `apps/api/priv/fiscal/ubl/2.1`, xmllint) and about 35 BIS 3.0 /
  EN 16931 business rules re-implemented in `test/support/peppol_bis_rules.ex`
  (BR-CO-17 uses the ±1 tolerance of the official Schematron).
- Storecove's credit-note `documentType` is sent as `invoice` with a UBL
  `CreditNote` body; to be confirmed.
- Sources: Peppol BIS Billing 3.0 (https://docs.peppol.eu/poacc/billing/3.0/),
  Peppol code lists / ICD (https://docs.peppol.eu/edelivery/codelists/),
  EN 16931 validation artefacts (https://github.com/ConnectingEurope/eInvoicing-EN16931),
  OASIS UBL 2.1 (https://docs.oasis-open.org/ubl/os-UBL-2.1/),
  Peppol in Belgium (https://efacture.belgium.be/en/peppol),
  Storecove API (https://www.storecove.com/docs/).

## Update 2026-10-29: fiskaly E-INVOICE replaces Storecove
Product owner decision (2026-10-29): fiskaly is the single vendor for fiscal
work outside Greece, so the access point is fiskaly E-INVOICE.

- **Adapter.** `Palee.Infrastructure.Fiscal.FiskalyEInvoiceNetwork` implements
  the same `EInvoiceNetwork` port; `fiskaly` is the default (and only
  non-sandbox) provider. The shared Unified API client is
  `Palee.Infrastructure.Fiscal.FiskalyUnified` (API version `2026-06-01`,
  `test.api.fiskaly.com` / `live.api.fiskaly.com`, bearer token from
  `POST /tokens` with the API key and secret). The Storecove adapter, its
  config and its tests are removed; the migrations are untouched and
  `storecove` stays an allowed `provider` value so old rows load. Such a row
  is marked invalid ("provider_retired: reconnect with fiskaly") and its
  documents wait as `connection_invalid` until the owner reconnects.
- **JSON, not UBL.** fiskaly does not accept an uploaded UBL file: it builds
  the Peppol BIS Billing 3.0 document (and XRechnung for Germany) from its
  own JSON record. Palee still builds and validates its UBL first (it is what
  the archive keeps and what the BIS rule tests check), then sends the same
  document as fiskaly JSON: an `INTENTION` record, then a `TRANSACTION`
  record of type `INVOICE` (buyer as a `BUSINESS` recipient with
  `invoicing.type = PEPPOL`, `scheme:identifier`), or a `CORRECTION` that
  points at the original invoice's fiskaly record id for a credit note. A
  credit note whose original was never sent through fiskaly is refused
  (`original_not_sent`). VAT rates map to the codes the business's fiskaly
  System lists (`STANDARD`, `REDUCED_n`), exemptions to its exemption codes;
  an unmapped rate or exemption is refused before anything is sent. The port
  takes the document and its original next to the UBL for this.
- **Status by polling.** fiskaly sends no webhooks for E-INVOICE: Palee polls
  `GET /records/{id}` and then the `E_INVOICE::TRANSMISSION` record named in
  `used_in` (`COMPLETED` + `FINISHED` = delivered; `REJECTED`/`FAILED` =
  failed). The webhook URL stays as a harmless hint endpoint.
- **Idempotency.** Every POST carries `X-Idempotency-Key`, a UUID v3 derived
  from the submission guid (`einvoice:<guid>:intention` / `:transaction`), so
  a staff retry of an uncertain submission replays the same request. fiskaly
  keeps keys for 24 hours: a 422 about the key, a 409 (in progress) or a
  timeout are uncertain and never resent by Palee itself. After 24 hours a
  staff retry is a new request, so staff must check fiskaly first (as before).
- **Credentials.** The connection stores an encrypted `api_key` and
  `api_secret` (new column, migration `20270222000000`), never returned or
  logged (`has_api_key`, `has_api_secret`, `credentials_source`). When the
  owner leaves them out, the fiskaly till connection's key and secret of the
  same environment are used (ADR-251) until the e-invoicing connection gets
  its own. `legal_entity_id` is now the business's fiskaly E-INVOICE System id
  (`E_INVOICE_SERVICE`, whose Peppol registration and proof of ownership are
  done once in the fiskaly HUB). The key must be a UNIT-level key of that
  business (no `X-Scope-Identifier` is sent).
- **Countries.** fiskaly E-INVOICE is live for Belgium (Peppol), Germany and
  Italy; France, Spain, Sweden and Austria are announced. Palee sends only
  where the country profile names Peppol (Belgium today); German B2B
  (EN 16931 / XRechnung) can use the same adapter once its policy is decided.
- Sources: fiskaly E-INVOICE integration guide
  (https://workspace.fiskaly.com/e-invoice/2026-06-01/integration-guide),
  Belgium (https://workspace.fiskaly.com/e-invoice/2026-06-01/belgium),
  Germany (https://workspace.fiskaly.com/e-invoice/2026-06-01/germany),
  example (https://workspace.fiskaly.com/e-invoice/2026-06-01/einvoice-example),
  OpenAPI specs
  (https://workspace.fiskaly.com/specs/fiskaly.uapi.e-invoice-be.2026-06-01.yaml,
  https://workspace.fiskaly.com/specs/fiskaly.uapi.e-invoice-de.2026-06-01.yaml),
  Postman collection
  (https://workspace.fiskaly.com/static/postman/E-INVOICE/fiskaly_e-invoice_be_2026-06-01_postman_collection.json),
  product page (https://www.fiskaly.com/e-invoice-germany).
