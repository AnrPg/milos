# ADR-074: Admin Finance and User Profile Usability
Date: 2026-07-31
Status: Accepted

## Context
Package codes were originally treated as the visible package identity across
finance surfaces. The product now treats the human package name as the primary
label, while the code is an optional operational identifier. The admin user
profile also aggregates finance, training, coaching, messaging, and health
records into one dossier, making dense sections hard to scan and causing edits
to feel disconnected from the canonical domain workspaces.

## Decision
Package `code` is optional and hidden behind an advanced disclosure in package
creation. Admin-facing relative surfaces should show package names where a live
package mapping is available, falling back to historical snapshots only when
needed. The admin user profile remains a read-oriented dossier, but editable
facts deep-link or reveal the canonical editing surface for their bounded
context rather than creating parallel ad-hoc editors.

## Rationale
Package names are the commercial language admins and users recognize. Optional
codes remain useful for imports, accounting, or legacy analytics, but should not
drive the primary UI. Keeping edits routed through canonical finance, schedule,
coaching, and admin-action surfaces avoids duplicate validation paths and keeps
persistence behavior consistent across the app.

## Alternatives Considered
Keeping package code required was rejected because it forces an internal label
into customer-facing admin workflows. Adding duplicate editors for every dossier
field was rejected because it would fragment validation and increase the chance
that one surface persists differently from another. Adding a new package-name
snapshot column was deferred because existing live package IDs can resolve the
name for current admin surfaces, while historical snapshots still provide a
safe fallback.

## Consequences
Existing packages with codes continue to work. New packages may omit a code, and
subscription creation must derive a safe non-empty historical code snapshot from
the package code, name, or family for existing not-null subscription constraints.
Future analytics can still group by the legacy snapshot, but primary UI labels
should prefer names. Deeper dossier edit affordances should continue to route to
the owning workspace or a bounded-context application service.

## Implementation Notes
ADR-075 amends the dossier navigation decision: small membership facts now edit
inline through the existing Finance mutation, while larger workflows remain in
their owning workspaces. The dossier no longer renders transparent deep links or
duplicates actions already reachable from its sections.

Initial implementation makes package code optional in the Ecto changeset and
OpenAPI contract, collapses the UI field, prefers package names in finance
tables and package assignment controls, refreshes relevant profile queries after
mutations, and softens the Paper theme toward an Aegean azure palette.

The admin user dossier now presents finance as a smaller set of summary cards
plus a canonical Finance workspace deep-link for edits, and coaching context as
scan-first status, assignment, note, score-trend, attention, recent-assignment,
and recent-note groups. This preserves one write path per bounded context while
making the profile page feel editable: clicked finance facts open the finance
member workspace, role changes keep using the existing role mutation, and
programming/coaching records point to their existing surfaces.

Validation notes: frontend TypeScript, focused admin/finance/profile tests,
document-export tests with an extended timeout for the heavy PDF/ODT case,
targeted ESLint, backend compile, and `mix milos.architecture` passed. The
DB-backed finance controller test command could not run locally because
PostgreSQL on `localhost:5432` refused connections; no assertion failure was
observed before the database creation failed.

Follow-up note: coaching-touchpoint package entitlements are also temporarily
blocked in package edits alongside Workout Library access. Existing
`coaching_touchpoints` allowances, including `unlimited`, are ignored by the
package editor sanitizer until the product has a plain-member/athlete surface
where admins can safely sell and users can actually consume that benefit.
