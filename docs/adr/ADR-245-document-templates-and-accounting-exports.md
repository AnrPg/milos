# ADR-245: Country document templates (PDF/HTML, Swiss QR-bill) and accounting exports
Date: 2026-10-29
Status: Accepted

## Context
Fiscal documents (ADR-241) existed only as data. Gyms must hand customers
a printable document carrying their country's mandatory mentions, Swiss
and Liechtenstein invoices are paid with the QR-bill, and Greek documents
must show the myDATA MARK/UID/QR (ADR-243). Their accountants then need
the period's documents in their own software: DATEV in DE/AT, Xero,
QuickBooks Online and Sage in English-speaking markets, bexio in CH
(docs/plans/government-fiscal-integrations.md). ADR-126 already exports
Finance's raw datasets (payments, allocations, reversals...) as a generic
ZIP, but no accounting package imports that as is.

## Decision
### Templates
1. `Palee.Fiscal.Templates.view/4` builds a neutral view of a document
   (`Domain.DocumentView`) from `Fiscal.get_document/2`, the corrected
   document, the transmission (`Reporting.transmissions_for/2`) and the
   seller's current bank details. Two renderers read it: `DocumentHtml`
   (self-contained A4 HTML, inline SVG QR codes) and `DocumentPdf`.
2. Mentions per country: seller identity with its country's ids (GR ΑΦΜ
   and ΔΟΥ, DE Steuernummer/USt-IdNr., FR SIREN/SIRET and TVA
   intracommunautaire, CH/LI UID, BE enterprise number, US EIN), buyer
   ids, the VAT breakdown by rate (net, tax, gross), exemption reasons per
   line, the small-business mention (§19 UStG, art. 293 B du CGI...), the
   corrected document's number and date on credit notes, FR "catégorie de
   l'opération" and late-payment penalties on B2B invoices, GR myDATA
   type names, MARK, UID, authentication code and QR code (or "reporting
   pending"), the journal fingerprint.
3. Labels are gettext messages of the `fiscal_documents` domain in el, en,
   de, fr, it, nl and es (`?language=` or the document's own language).
4. **Swiss QR-bill** (`Domain.QrBill`), per SIX Implementation Guidelines
   v2.4: structured addresses (type `S`) only; QR-IBAN with a 27-digit QR
   reference (mod 10 recursive) in CHF, or a CH/LI IBAN with an ISO 11649
   creditor reference (`SCOR`, `RF..`) in CHF or EUR; the 31-line payload
   `SPC/0200/1` in the exact order, LF separated, no trailing separator,
   character set and field lengths enforced; QR code error correction M,
   46×46 mm with the 7×7 mm Swiss cross; receipt (62 mm) and payment part
   (148 mm) with the guideline's fonts sizes and headings in de/fr/it/en.
   A QR-bill is printed on invoices to be paid (payment method none or
   bank transfer) of a CH/LI seller with an IBAN.
5. Bank details: `fiscal_business_identities.iban` and `qr_iban`
   (nullable), validated by country length and mod 97; a QR-IBAN (IID
   30000–31999) is only accepted as `qr_iban` and only in CH/LI.
6. PDF: a small deterministic PDF 1.7 writer (`Palee.Pdf`) embedding
   subset Liberation Sans (SIL OFL, `priv/fonts`) as CID TrueType with a
   ToUnicode map, so Greek and every Latin script prints and is
   searchable. QR codes come from `eqrcode` 0.2.1 (pure Elixir, no NIFs):
   no QR library was in the dependencies.
7. Endpoints: `GET /admin/fiscal/documents/:id/pdf` and `/html`
   (`?language=`), capability `view_finance_reports`.

### Accounting exports
8. Port `Fiscal.Ports.AccountingExportFormat` (`id/0`, `describe/0`,
   `normalize_options/1`, `render/2`); adapters in
   `Infrastructure.Fiscal.Exports`, listed in
   `config :palee, :fiscal_accounting_export_formats`. They render the
   neutral `Domain.ExportEntries`: per document its signed totals
   (credit notes negative), VAT groups and lines, plus Finance payments
   (ADR-126 `payments` dataset, net of reversals).
9. Formats:
   - **DATEV** Buchungsstapel: EXTF header (version 700, category 21,
     format version 9), the 120 Buchungsstapel columns, Windows-1252,
     semicolons, decimal comma, `Belegdatum` TTMM; one booking per
     document and VAT rate, gross, `S` (credit notes `H`) from cash, bank
     or receivables to the revenue account. SKR03/SKR04 default revenue
     accounts per category (Automatikkonten 8400/8300, 4400/4300; exempt
     8100/4100; zero 8120/4120; Kleinunternehmer 8195/4185), all
     overridable, BU keys optional; Beraternummer and Mandantennummer
     required. Payments optional.
   - **Xero**: the 27-column sales invoice import, one row per line,
     credit notes with a negative unit amount, tax-inclusive amounts.
   - **QuickBooks Online**: invoice import CSV, one row per line, net
     amounts with the line tax; credit notes cannot be imported and are
     counted as skipped.
   - **Sage 50 / Business Cloud**: audit trail transactions CSV, `SI`/`SC`
     per document and rate with T-codes, optional `SA` receipts.
   - **bexio**: manual bookings CSV (Datum, Belegnummer, Buchungstext,
     SollKonto, HabenKonto, Betrag, MWST, Währung), gross amounts with the
     bexio tax code (UN81, UN26, UN38 by default).
   - **CSV** and **JSON**: Palee's own flat line/payment rows and the
     entries as they are.
10. Each gym keeps its options per format in `fiscal_export_settings`
    (validated against the adapter's option list, journaled as
    `export_settings_saved`). An export is a synchronous download of at
    most 366 days, journaled as `accounting_exported` with its SHA-256.
    Headers `x-palee-export-documents`, `-payments`, `-skipped`.
11. Endpoints (reads `view_finance_reports`, writes `manage_billing`):
    `GET /admin/fiscal/exports/formats`,
    `PUT /admin/fiscal/exports/settings/:format`,
    `GET /admin/fiscal/exports/:format?from&to`.

## Rationale
One view and two renderers keep HTML and PDF in step and testable without
a browser. Writing the PDF ourselves (≈600 lines) avoids a headless
Chrome or wkhtmltopdf in production and gives byte-exact, millimetre
layout for the QR-bill, which banks scan. Synchronous exports match the
audit archive: a year of a gym's documents is a few thousand rows, while
the ADR-126 job and storage flow belongs to Finance and its datasets.
Formats as adapters let a new country's package be added without touching
the domain.

## Alternatives Considered
- **HTML to PDF via headless Chrome / wkhtmltopdf / Gotenberg**: heavy
  runtime dependency, non-deterministic output. Rejected.
- **An Elixir PDF library** (`pdf`, `elixir-pdf`): no TrueType embedding
  for Greek, no subsetting. Rejected.
- **Reusing the ADR-126 export job table**: Finance-owned, its manifest
  and datasets are Finance's; fiscal exports would need cross-context
  writes. Rejected for now; a large range can move to an Oban job later.
- **DATEV format version 13** (125 columns): the official DATEV developer
  portal could not be read; version 9 is what open-source exporters
  (ERPNext) ship and DATEV still imports. To confirm with a DATEV user.
- **Xero/QuickBooks APIs** instead of files: OAuth apps per package; files
  first, APIs when a pilot asks.

## Consequences
- Exports are only as good as the gym's mapping (accounts, tax codes);
  the defaults follow the standard charts and must be checked by each
  gym's accountant.
- Documents in other currencies than the seller's are exported as is
  (no exchange rate column filled).
- QuickBooks gets no credit notes; Xero/QuickBooks/Sage get no payments
  (they reconcile from the bank feed), DATEV, Sage and bexio optionally.

## Implementation Notes
- Sources:
  - SIX, Swiss Implementation Guidelines QR-bill v2.4:
    https://www.six-group.com/dam/download/banking-services/standardization/qr-bill/ig-qr-bill-v2.4-en.pdf
  - DATEV format (EXTF/DTVF): https://developer.datev.de/datev/platform/en/dtvf
    and https://developer.datev.de/datev/platform/en/dtvf/einstieg;
    Buchungsstapel columns as in ERPNext
    https://github.com/frappe/erpnext/blob/version-13/erpnext/regional/germany/utils/datev/datev_constants.py;
    header field order discussed at
    https://www.datev-community.de/t5/Betriebliches-Rechnungswesen/Sachkonto-als-Ascii-ausgeben/m-p/366618
  - Xero sales invoice import: https://central.xero.com/s/article/Import-customer-invoices
    (column list cross-checked with https://syslumelab.com/guides/xero-sales-invoice-import-csv)
  - QuickBooks Online invoice import:
    https://quickbooks.intuit.com/learn-support/en-us/help-article/import-export-data-files/import-multiple-invoices/L7E9Xrd8l_US_en_US
  - Sage 50 audit trail import fields:
    https://gb-kb.sage.com/portal/app/portlets/results/viewsolution.jsp?solutionid=250321114601443
    and https://import.makingithappen.co.uk/csv_audittrans.htm
  - bexio manual bookings: https://help.bexio.com/s/article/000001672?language=de
    (fields), https://importly.ch/blog/buchungsimport-vorlage-bexio (CSV templates)
- The bexio and Sage column names come from secondary sources; the DATEV
  account defaults and bexio tax codes are to be confirmed with an
  accountant (open questions in the V3-M3 report).
