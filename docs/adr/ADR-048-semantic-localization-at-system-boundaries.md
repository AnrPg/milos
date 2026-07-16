# ADR-048: Semantic localization at system boundaries
Date: 2026-07-16
Status: Accepted

## Context

Phase 2 completed application-owned React copy and structural RTL behavior, but
text also reaches users through API failures, canonical enum values, Web Push,
the Service Worker, calendar exports, PWA metadata, and backend-built read-model
descriptions. These surfaces execute in different runtimes and some are created
when no browser is available. Translating stored enum values or user-authored
content would corrupt durable data, while returning only English prose from the
API makes browser-side translation unreliable.

The solution must preserve bounded-context ownership, contract-first APIs,
offline behavior, stable machine values, and the single-copy path shared by
in-app notifications and Web Push.

## Decision

Use semantic values across runtime boundaries and localize at the final
human-presentation boundary:

1. API failures expose a stable `code` and interpolation `params` alongside the
   existing English `error` compatibility field. Frontend error presentation
   resolves known codes through the ICU catalog and falls back safely for
   unknown or legacy responses. Validation field names and reasons are carried
   as semantic data rather than assembled into display prose by controllers.
2. Database enums, API enum values, notification types, score units, and state
   identifiers remain canonical and untranslated. A central frontend semantic
   formatter maps every value that can be displayed to a catalog message; raw
   values remain available for logic, persistence, filtering, and contracts.
3. Notifications persist semantic type plus normalized payload facts. The
   Notifications context renders title and body in the recipient's
   `preferred_locale` when creating the shared in-app/Web Push presentation.
   Phoenix Gettext owns this server-rendered copy, with English fallback.
4. Server-generated artifacts such as calendar feeds use the requesting user's
   persisted locale and Phoenix Gettext. PWA manifest metadata is selected from
   the resolved web locale. The Service Worker receives already-localized push
   payloads and retains only a language-neutral product-name/empty-body fallback
   for malformed or legacy payloads.
5. User/admin-authored titles, notes, chat, names, and descriptions remain
   verbatim and are rendered with bidirectional isolation. No global dynamic
   translation table is introduced.
6. Completeness gates inventory semantic display mappings, backend Gettext
   catalogs, service-worker/PWA fallbacks, and generated artifacts in addition
   to the Phase 2 TSX/catalog checks.

## Rationale

Semantic codes keep API contracts useful to every client without making API
responses depend on presentation language. Localizing enums only where they are
shown prevents translated strings from leaking into filters or persisted data.
Recipient-time notification rendering is deterministic for background jobs and
keeps the in-app and push message identical. Gettext is already the approved
Phoenix localization mechanism and supports interpolation and plural rules
without introducing a cross-context database owner.

## Alternatives Considered

Localizing every API response from `Accept-Language` was rejected because it
mixes transport and presentation, complicates caching, and deprives clients of
stable failure semantics.

Matching translated frontend errors against English backend prose was rejected
because wording changes would silently break translation and validation details
would remain difficult to interpolate safely.

Translating enums in PostgreSQL or returning localized enum values was rejected
because durable state and API contracts must remain stable across locale
changes.

Maintaining a second complete notification catalog in JavaScript was rejected
because background delivery is backend-owned and duplicate message ownership
would drift.

## Consequences

Error envelopes gain additive fields and must be documented before controller
changes. The frontend must treat unknown codes defensively during the migration.
Every newly displayed canonical value requires a semantic formatter entry.
Notification and export rendering must receive locale explicitly instead of
consulting process-global state.

Backend Gettext catalogs become release artifacts for all twelve locales.
Translation completeness is mechanically enforceable, but linguistic review
remains a product-quality responsibility rather than a runtime dependency.

## Implementation Notes

Implementation preserved the additive API compatibility field while introducing
top-level `code` and optional `params` envelopes across fallback controllers,
authentication, authorization, rate limiting, execution, and default error JSON.
The OpenAPI components and generated TypeScript schema were regenerated from the
updated contract. Browser presentation never displays backend compatibility
prose: known codes resolve through the catalog and unknown legacy failures use a
localized status-class fallback.

The frontend semantic presentation layer now owns roles, statuses, workout and
timer types, scales, finance values, units, score snapshots, and other canonical
identifiers. A second implementation audit found and removed expression-built
fragments such as plural suffixes, measurement units, member/person/athlete
counts, transient error text, and accessibility labels. The TSX copy gate was
extended to detect composed lowercase display literals, and the catalog
generator now restores ICU plural control syntax after machine translation.
The final catalog contains 2,194 messages in each of the twelve locales with
key, non-empty-value, ICU placeholder, and hard-coded-copy parity enforced.

Phoenix localization remains behind `MilosTraining.Localization`, whose Gettext
adapter normalizes the persisted `pt-PT` locale to Gettext's `pt_PT` directory.
Three backend domains ship complete catalogs in every locale: notifications
(33 messages), calendar (13), and sharing (7). Notification title/body rendering
occurs once for the recipient locale before the same persisted presentation is
used by in-app and Web Push delivery. Authored names, titles, messages, and notes
remain verbatim. Calendar help/feed copy and PR share text use the persisted
recipient locale; dates use locale-neutral ISO representation where no browser
formatter exists.

The initial idea of a second Service Worker fallback catalog was deliberately
dropped during implementation because it would duplicate backend-owned
notification copy. Push payloads now include locale, title, body, URL, and RTL
direction inputs; malformed legacy payloads fall back only to the product name
and an empty body.

Verification completed with 407 backend tests, architecture and warning-as-error
compile gates, 13 frontend tests, lint, type checking, a production Next.js
build, 2,194-message catalog validation, and backend Gettext validation. Live
production checks passed for Arabic admin RTL, Greek member LTR, and Hebrew
athlete RTL with no horizontal overflow or raw system-label leakage. An English
`not_found` compatibility response rendered as Arabic semantic copy; the Arabic
manifest exposed localized description plus `lang=ar`/`dir=rtl`; Greek calendar
subscription help rendered from the persisted user locale. A pre-existing local
MinIO avatar URL/CSP mismatch discovered during the live run is recorded as
TD-032 and does not affect localization behavior.
