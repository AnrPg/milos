# ADR-265: Credit note reason and refund to the card, emailing a fiscal document, filling in from the ΑΦΜ
Date: 2026-10-29
Status: Accepted

## Context
The approved mockups of the fiscal screens (V3 s1 C and s2 A) have three
things the fiscal core (ADR-240–245, ADR-262) did not offer, so the
screens shipped without them:

1. the credit-note panel asks **why** («Λόγος»: Επιστροφή προϊόντος, Λάθος
   χρέωση, Ακύρωση συνδρομής, Άλλο) and, for a document paid by card
   online or with Tap to Pay, offers «Επιστροφή χρημάτων στην κάρτα» in
   the same action;
2. every document has «Αποστολή με email»;
3. the billing details (s1) offer «Συμπλήρωση από το ΑΦΜ»: AADE's
   registry fills in the legal name, ΔΟΥ, address and ΚΑΔ.

## Decision

### 1. Credit note reason
- `fiscal_documents.credit_reason` (nullable string, check constraint:
  only on credit notes, one of `product_return`, `billing_error`,
  `subscription_cancelled`, `other`). It is written when the note is
  inserted; the table stays insert-only (ADR-241).
- The reason is part of the issued document: it is in the content hash
  (only when present, so every earlier document keeps its hash), in the
  `document_issued` journal payload, and in the request hash of the
  idempotency key (only when present, so ADR-262 reversal keys in flight
  keep theirs). `Fiscal.credit/8` takes `reason:`.
- Staff always give it: `POST /admin/fiscal/documents/:id/credit-notes`
  requires `reason`. Notes issued by a plain refund (ADR-262) carry none.
- It is printed on the document («Λόγος πιστωτικού», gettext
  `fiscal_documents` in the 7 document languages).
- **myDATA** (v2.0.1, `InvoicesDoc`) has no field for a correction reason:
  a credit note carries only `correlatedInvoices` (the MARK). Nothing is
  sent. **Peppol/UBL**: the reason goes as the document note `cbc:Note`
  (BT-22, at most one per PEPPOL-EN16931-R002) in the document's language;
  UBL's `DiscrepancyResponse` is not part of Peppol BIS Billing 3.

### 2. Refund to the card
- `GET /admin/fiscal/documents/:id` adds `refund_option`
  (`provider, card_brand, card_last4, refundable_cents`) when the document
  is a Finance payment's receipt (ADR-262) whose payment intent (online or
  terminal, ADR-246/249) succeeded and has money left to give back.
- `refund: true` on the credit-note request does **not** issue a note
  itself: the refund issues it, as every refund does (ADR-262), so one
  action never makes two notes. `Application.Fiscal.CreditRefunds`:
  1. computes the note the request would issue (`Fiscal.credit_preview/4`)
     and refunds exactly its gross (`Payments.refund`, key
     `fiscal-credit:<panel key>`);
  2. the refund carries `fiscal_credit` (new `payment_refunds.fiscal_credit`
     map: the reason and, for a partial note, the chosen lines), an opaque
     value Payments hands to the fulfilment's `reverse`;
  3. `PaymentDocuments.credit/5` issues the note from it: exactly the
     chosen lines (not an amount spread over all lines) with the reason.
- The answer is `{document, refund}`; `document` is the note the refund
  issued (`finance-reversal:<id>`), null if the refund could not issue it
  yet. A repeat with the same key returns the same refund and note.
  `refund_not_available` (409) for a document not paid that way.

### 3. «Αποστολή με email»
- `POST /admin/fiscal/documents/:id/email` (`manage_billing`) with
  `idempotency_key`, optional `to` (else the buyer's email printed on the
  document; `no_recipient` when neither) and `language`.
- Through the email outbox (ADR-203): new kind `:fiscal_document`
  (transactional, so a demo business cannot send, ADR-184), localised in
  the `emails` domain for all 12 locales, rendered in the document's
  language. The outbox gains **attachments**: `enqueue(..., attachments:
  [%{filename, content_type, data}])`, PDF only, at most 5 MB in all,
  stored base64 **inside the encrypted body** and therefore cleared with it
  once the email is sent or given up on. The sender port passes them to
  Swoosh.
- Rate limits: the template's per-address throttle (10 a day, 30 s apart)
  and 20 requests a minute per staff member on the route.
- Idempotent: outbox key `fiscal_document:<document id>:<key>`.
- Audited: one `document_emailed` journal entry per send (recipient kind
  `buyer`/`address`, a SHA-256 digest of the address, never the address:
  the journal is never erased; the outbox message id), written in the same
  transaction as the outbox row.

### 4. «Συμπλήρωση από το ΑΦΜ»
- Port `Fiscal.Ports.BusinessRegistry.lookup(connection, tax_id, as_on)`;
  adapters by connection environment (`config :palee,
  :fiscal_business_registries`): `SandboxBusinessRegistry` (made-up active
  business for any valid ΑΦΜ; ending `0000` = not found) and
  `AadeRegistry`: AADE's **RgWsPublic2** SOAP 1.2 service
  (`https://www1.gsis.gr/wsaade/RgWsPublic2/RgWsPublic2`, operation
  `rgWsPublic2AfmMethod`, WS-Security `UsernameToken`, input
  `afm_called_for` + `as_on_date`), reading `basic_rec` (onomasia,
  commer_title, doy/doy_descr, postal address, deactivation_flag,
  normal_vat_system_flag) and `firm_act_tab` (ΚΑΔ, kind 1 = main).
  `RG_WS_PUBLIC_*` error codes map to `credentials_rejected`, `not_found`,
  `limit_reached`, `unavailable`.
- Credentials are the business's own «ειδικοί κωδικοί» for this service:
  stored like the myDATA connection (ADR-243) as a row of
  `fiscal_authority_connections` with authority `gr_registry`
  (environments `sandbox`, `production`), the password encrypted
  (`EncryptedBinary`), never returned, logged or journaled
  (`registry_connection_saved` journals only the user and whether the
  password changed). Refused credentials mark the connection `invalid`.
- The ΑΦΜ's check digit is verified before any call (`invalid_tax_id`), so
  a typo never spends the business's AADE quota.
- API: `GET/PUT /admin/fiscal/registry-connection`,
  `GET /admin/fiscal/registry/businesses/:tax_id` (`manage_billing`, 30 a
  minute per staff member). Used by the business group of the billing
  details (s1); the same call serves an invoice buyer's details.

## Rationale
- A reason inside the immutable document is what NF525/GoBD-style auditors
  and EN 16931 expect; hashing it only when present keeps the chain of
  every earlier document valid without a migration of hashes.
- Letting the refund issue the note keeps ADR-262's single path from money
  to documents: two code paths that both issue notes would double-credit
  sooner or later.
- Attachments inside the encrypted body reuse the outbox's guarantees
  (one transaction, retries, clearing) without a new table or object store.
- The business's own credentials are what AADE's terms require; a
  platform-wide account would query on behalf of others.

## Alternatives Considered
- **Issue the note in the panel, then refund with "no note"**: needs a
  flag through Payments and Finance that skips ADR-262; the two halves can
  disagree when the provider refuses. Rejected.
- **Amount-based note for a refunded partial note**: simpler, but spreads
  the amount over every line and tax group instead of the chosen lines.
  Rejected.
- **A link to the PDF instead of an attachment**: needs a public, signed
  URL to a legal document and expires; customers expect the file. Rejected.
- **Unofficial ΑΦΜ look-up sites / VIES**: VIES gives only name and
  address of VAT-registered businesses, no ΔΟΥ or ΚΑΔ; scraping is
  unreliable. Rejected.

## Consequences
- Migration `20270224000000_v3_fiscal_extras.exs`.
- The staff screens get the reason chips, the refund switch, the email
  dialog and the look-up button (mockups s1 C, s2 A).
- There is no screen yet for entering the AADE registry credentials (the
  myDATA connection has none either): until it comes they are saved with
  the API, and the look-up says what is missing.
- The email is throttled per address; a business that sends many
  documents to its accountant should export instead (ADR-245).

## Implementation Notes
- Sources: AADE RgWsPublic2 terms and FAQ (aade.gr, 2018-07), the
  endpoint/WSDL and the request/response element names as used by
  open-source clients (github.com/kamilakis/rgwspublic,
  pkg.go.dev/github.com/kamhlos/rgwspublic); myDATA XSD v2.0.1 in
  `priv/fiscal/mydata`; UBL 2.1 and Peppol BIS Billing 3 rules in
  `priv/fiscal/ubl`.
