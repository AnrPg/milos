# ADR-072: Document export rendering hardening
Date: 2026-07-31
Status: Accepted

## Context

ADR-065 established a shared browser-side document model and local PDF renderer
for workout definitions, workout history, and personal records. The current PDF
output is difficult to read: it lacks a dependable visual hierarchy and can
clip or omit long content. The same rendering expectations apply to the admin
finance member export.

## Decision

Keep export generation private and browser-local, but harden the shared PDF
renderer around a deterministic layout contract: a repeated document header,
explicit heading and body typography, paragraph spacing, page-aware wrapping,
and continuations for content that does not fit on the current page. Extend the
canonical presentation model where needed so every source supplies complete
textual content before rendering.

All PDF-producing export surfaces will use this renderer rather than carrying
per-screen PDF layout logic.

## Rationale

A single, page-aware renderer preserves the privacy and no-backend-upload
decision in ADR-065 while eliminating duplicated, inconsistent PDF styling.
It makes long workout prescriptions and member data reliable without requiring
the browser to print a transient application page.

## Alternatives Considered

Using the browser print dialog was rejected because printed application screens
are not a stable document format and can include navigation or omit virtualized
content.

Moving generation to the server was rejected because it would add artifact
storage, authorization, cleanup, and cross-context read orchestration without
improving the source data already available to the authorized browser.

## Consequences

Export tests must verify pagination and the presence of long source text, not
only that the generated blob has a PDF signature. The renderer owns typography
and page breaks; source adapters own only complete, semantic data.

## Implementation Notes

Implemented on 2026-07-31. The shared jsPDF renderer now wraps metadata,
headings, values, and detail paragraphs without truncation; a block can continue
across as many pages as necessary. Continuation pages carry a compact document
header, while all pages have a footer and page number. Labels and values have
separate visual treatment, producing a clear hierarchy for workouts, execution
history, PRs, and any future source adapter.

The Finance members table now exposes the same Share / Export dialog. Its
adapter includes every column presented in the table, including membership,
plan, payment, balance, notes, and referral information, and exports the active
filtered result set.

Verification completed with document-export and sharing-dialog tests, TypeScript
checking, localization validation, and a production Next.js build. No technical
debt entry was added.
