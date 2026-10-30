# ADR-241: Immutable fiscal documents, gapless series, VAT by rate group
Date: 2026-10-29
Status: Accepted

## Context
Every MVP country requires that a sale produces a numbered document that is
never changed afterwards: Greek ΑΠΥ/ΤΠΥ reported to myDATA, French NF525
(corrections only by records of the opposite sign), German GoBD, Swiss and
UK VAT rules. Finance invoices (ADR-126) are working documents: they can be
voided, re-issued and their status moves. They cannot be the legal record.

## Decision
1. **`fiscal_documents` and `fiscal_document_lines` are insert-only.** A
   database trigger rejects every `UPDATE` and every `DELETE` except a tenant
   purge after the retention period (session flag
   `palee.fiscal_purge = 'on'`, set only by Fiscal's purge). Transmission
   state (ADR-243) lives in its own tables.
2. **Kinds**: `receipt` (retail, buyer optional), `invoice` (buyer with name
   and address required, B2B), `credit_note` (refers to the document it
   corrects; the sum of credit notes never exceeds the original, per line).
   Cancelling a document is a full credit note.
3. **Series and numbers**: one gapless sequence per organization and series
   (`fiscal_sequences`, row locked `FOR UPDATE` in the issuing transaction,
   so a rollback returns the number). The series key is the kind's prefix
   plus the branch code (`R`, `I`, `C`; `R1` for branch 1); the printed
   number is `<series>-<sequence padded to 6>`. Series and sequence are also
   stored apart because myDATA sends them as separate fields.
4. **Money**: integer minor units and ISO 4217 currency (EUR, CHF, GBP, USD).
   Each line carries a tax category, its rate in basis points (2400 = 24 %)
   and whether its price includes tax. **VAT is computed per rate group**,
   rounded half up, as EN 16931 requires; the group's net is then shared out
   over its lines by largest remainder, so lines, groups and totals always add
   up to the cent. Rates come from `Fiscal.Domain.VatRates` by country,
   category and date (ADR-244 makes it a full tax engine).
5. **Snapshots**: the seller (the identity at the time of issue) and the buyer
   are copied into the document, so later edits never change an issued one.
6. **Idempotent issue**: callers send an `idempotency_key` (unique per
   organization). A retry returns the first document. A key reused with
   different content is refused (`idempotency_key_reused`).
7. **Source link**: `source_type`/`source_id` on the document and lines name
   what caused it (Finance payment, shop order). Fiscal never reads those
   tables.
8. **API**: `GET /admin/fiscal/documents` (filters: kind, date range, number),
   `GET /admin/fiscal/documents/:id`, `POST /admin/fiscal/documents/:id/credit-notes`
   (capability `manage_billing`; all lines or chosen quantities).

## Rationale
- Insert-only plus a trigger makes "never changed" a database fact, not a
  convention, which is what NF525 and GoBD auditors ask to see.
- Per-group VAT is the only rounding that matches Peppol/EN 16931 validators
  and the myDATA totals check.
- Snapshots are the standard way to keep a document's meaning stable.

## Alternatives Considered
- **Making Finance invoices immutable**: they serve dunning, credits and
  corporate billing and change status by design. Rejected.
- **Per-line VAT rounding**: simpler, but EN 16931 rule BR-CO-17 and myDATA
  totals reject cent differences on documents with many lines. Rejected.
- **UUIDs as numbers**: every country requires a human, continuous number.

## Consequences
- Finance and Shop ask Fiscal for the document of a sale (wired in V3-M2 with
  myDATA, so the two are switched on together).
- Wrong documents are corrected only with credit notes, also in the UI.
- PDF rendering per country comes with ADR-245.

## Implementation Notes
- Migration `20270201000000_create_fiscal.exs`.
