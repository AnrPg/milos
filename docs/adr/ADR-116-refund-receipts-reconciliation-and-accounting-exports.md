# ADR-116: Refund Receipts, Provider Reconciliation and Accounting Exports
Date: 2026-10-12
Status: Accepted

## Context
ADR-019 made payment refunds/reversals append-only `finance_payment_reversals`
facts and explicitly deferred refund receipts, external payment-provider
reconciliation and accounting exports (TD-022). The product is still
manual-payment first: there is no provider API integration and no server-side
PDF library (invoice PDFs are rendered in the browser with jsPDF, ADR-072;
uploaded invoice documents live in MinIO under `organizations/<id>/invoices/`).
Any new artifact must attach to the existing facts without changing core
columns, stay tenant-isolated under forced RLS (ADR-091/ADR-109) and be covered
by the ADR-107 retention/purge policy.

## Decision
Add three additive, Finance-owned artifacts on top of the reversal facts:

1. **Refund receipts** (`finance_refund_receipts`). Every reversal that returns
   money (`refund`, `payment_reversal`) gets exactly one immutable receipt,
   issued inside the reversal's own transaction. Numbers come from a per-tenant
   counter row (`finance_document_counters`, document type `refund_receipt`)
   that is upserted and locked `FOR UPDATE` in that transaction, giving gapless
   per-organization numbers `RFD-000001`, `RFD-000002`, ... A receipt stores the
   reversal/payment/invoice links, amount, currency, reason, issuer and
   timestamps plus an immutable JSON snapshot (organization and member names,
   reversal, original payment, invoice, running totals) and the SHA-256 of its
   canonical encoding. A DB trigger rejects any change to accounting columns.
   The document is a deterministic, self-contained printable HTML page rendered
   from the snapshot in the viewer's locale (new `receipts` gettext domain);
   staff read tenant receipts, members only their own.
2. **Reconciliation records** (`finance_reconciliation_records`). A
   provider-agnostic statement line (provider key, external reference,
   `payment`/`refund`, provider status, amount, currency, date, description),
   idempotent on `(organization_id, provider, external_reference)`. Staff
   match a line to exactly one internal payment (payment lines) or reversal
   (refund lines); pure domain rules record `matched` or `mismatched` with
   discrepancy codes (type, amount, currency, date tolerance of 3 days,
   provider not settled, internal payment not paid). Partial unique indexes
   keep one statement line per internal fact. Internal facts are never
   modified.
3. **Accounting exports** (`finance_accounting_exports`). An export for an
   inclusive date range produces one CSV (RFC 4180, CRLF, formula-guarded) and
   one JSON document per dataset - `payments`, `allocations`, `reversals`,
   `credits`, `refund_receipts` - with versioned column schemas
   (`schema_version` 1, documented in `Finance.Domain.AccountingExport`), plus a
   `manifest.json` with per-file SHA-256, size and row counts, zipped and
   stored through `TenantObjectStorage` at
   `organizations/<id>/finance/accounting-exports/<run>/accounting-export.zip`.
   Each run records requester, range, mode, status, object key, size, SHA-256,
   file manifest and row counts. Ranges up to 31 days build in the request;
   longer ranges (max 1830 days) run in `BuildFinanceAccountingExportJob`.
   Downloads use 15-minute signed links.

## Rationale
Issuing receipts in the reversal transaction makes "every refund has a
receipt" and "numbers have no gaps" hold by construction: the counter, the
reversal and the receipt commit or roll back together, and concurrent issuers
queue on the counter row lock. A dedicated counter table (rather than a
PostgreSQL sequence like `finance_invoice_number_seq`) is required because
sequences are non-transactional and global. Snapshotting the party names makes
the receipt self-contained and lets the HTML be byte-for-byte reproducible
without cross-context reads at render time. HTML instead of PDF avoids a new
dependency while remaining printable/saveable as PDF from any browser.

A provider-agnostic line keyed by the provider's own reference lets future
provider integrations (webhooks, statement imports) write the same rows
idempotently; keeping matching rules pure keeps them unit-testable and
identical for manual and automated flows. Linking rather than mutating keeps
ADR-019's append-only guarantee.

A single checksummed ZIP gives accountants one artifact with one integrity
value while still exposing plain CSV files; a stable, versioned column schema
lets downstream imports rely on it. Storing it under the tenant prefix reuses
ADR-107's prefix-pinned inventory, purge and signed-link machinery.

## Alternatives Considered
- **Receipt as a separate post-commit step or Oban job**: rejected; a crash
  between reversal and receipt would leave refunds without receipts and
  complicate gapless numbering.
- **PostgreSQL sequence per tenant / global sequence**: rejected; sequences
  leak values on rollback (gaps) and per-tenant sequences need DDL at tenant
  creation.
- **Server-side PDF**: rejected; no PDF library is a dependency and adding one
  was out of scope. The browser jsPDF renderer (ADR-072) serves client-built
  documents; refund receipts need a server-authoritative rendering.
- **Mutating payment/reversal rows with provider references**: rejected; it
  changes core schema and breaks the append-only facts.
- **Separate CSV/JSON objects instead of a ZIP**: rejected for v1; ten signed
  links and ten checksums per run add UI and audit noise. Per-file checksums
  are still recorded.
- **Retaining export artifacts in the purge**: rejected; they are derived from
  the retained Finance tables (and the run audit rows, with their checksums,
  are themselves retained), so they are purged with other tenant documents.

## Consequences
- Every payment reversal response now also returns `refund_receipt` (nil for
  waiver reversals). The Finance store's reversal return value is unchanged.
- New tenant tables are declared in Finance's `TenantDataPolicy` (10-year
  retention, deleted before reversals/payments) and classified ready in
  `mix milos.tenancy.audit`.
- Receipts are immutable; a wrong receipt is corrected by a new reversal fact
  (and its own receipt), never by editing. Receipts of soft-deleted reversals
  (ADR-084) leave normal views but their rows remain.
- Exports are built in memory, like the ADR-107 tenant export.
- Provider integrations must write `finance_reconciliation_records` through the
  Finance API; they must not alter payment or reversal rows.

## Implementation Notes
- Migrations `20261014150000` (counters + receipts, immutability trigger
  `milos_finance_refund_receipts_immutable`, which still allows FK
  `SET NULL` on `finance_invoice_id`/`issued_by_id`), `20261014150100`
  (reconciliation records) and `20261014150200` (export runs) are additive and
  mirror sibling finance tables: `milos_apply_tenant_context()` trigger,
  bare-equality `<table>_tenant_policy`, ENABLE + FORCE RLS, `organization_id`
  cascading from `organizations`. The range moved from `20261012150000` to
  `20261014150000` to avoid a parallel branch's version.
- New port/facade/adapter `Finance.Ports.FinanceAccountingStore` /
  `Finance.FinanceAccountingStore` / `Infrastructure.Finance.EctoFinanceAccountingStore`
  (added to the architecture task's tenant-scoped store list) keeps the
  4,000-line `EctoFinanceStore` from growing; the only change there is the
  receipt issuance call inside `reverse_payment/3`.
- The reversal Application Service resolves the organization name from the
  tenant context and the member display name from Identity and passes them as
  `receipt_party`; client-supplied values are always overwritten.
- `Identity.find_by_id/1` returns an account struct without
  `display_nickname`, so names fall back to `nickname`.
- Waiver reversals get no receipt (no money moved). Reversals recorded before
  this change have no receipt; replaying one lazily issues it.
- Receipt HTML is served as `text/html` with `default-src 'none'` CSP,
  `no-store` and `nosniff`; the web app previews it in a fully sandboxed
  iframe and opens a blob copy for printing.
- Concurrency evidence: integration tests cover sequential gapless numbering,
  per-tenant independence, idempotent replays and a rolled-back reversal
  releasing its number. A true multi-connection race test is not possible
  inside the Ecto SQL sandbox; the row lock is the mechanism.
- Verification: `mix precommit` (gettext catalogs incl. `receipts`, compile
  with warnings as errors, architecture, Credo, Dialyzer, unused deps, format,
  1018 tests, 0 failures), `MIX_ENV=test mix milos.tenancy.audit`, and web
  lint, type-check, 272 vitest tests, `i18n:check`, contract regeneration and
  production build. The full ExUnit run needed `ELIXIR_ERL_OPTIONS="+fnu
  +MIscs 4096"` on this machine: with the default literal super carrier the
  BEAM aborted late in the run with `literal_alloc: Cannot allocate ...` (an
  environment limit, not a test failure).
- Deferred: provider API/webhook ingestion and bulk statement-file import;
  automatic matching; backfilling receipts for historical reversals; streaming
  exports for very large tenants; analytics events for reconciliation/export
  actions; PDF rendering of receipts.
