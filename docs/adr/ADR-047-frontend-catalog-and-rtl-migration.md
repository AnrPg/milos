# ADR-047: Frontend catalog and RTL migration
Date: 2026-07-16
Status: Accepted

## Context

Phase 1 established the locale foundation, but the application still contains a
large amount of application-owned frontend text mixed with layout assumptions
that only work correctly in left-to-right rendering. The Phase 2 rollout needs
to complete the user-facing frontend migration without introducing a separate
runtime translation database or breaking the bounded-context ownership model.

The remaining surfaces are heterogeneous: schedule and booking flows, workout
browsing and authoring, execution/offline states, landing/gamification, finance,
coaching, reviews, wellbeing, messaging, admin tooling, and empty/error/loading
states. They also include date/time/currency formatting, pluralization, and
direction-sensitive controls such as drawers, tables, calendars, and action
icons.

## Decision

Migrate the frontend in coherent feature slices backed by the existing ICU
catalog system and RTL foundation:

1. Classify every user-facing frontend string into one of four buckets:
   application UI copy, formatted values, backend errors, or unstructured user
   text.
2. Replace application UI copy with stable semantic catalog keys in the twelve
   supported locales.
3. Replace manual string concatenation and locale-neutral formatting with
   locale-aware ICU messages and formatter helpers.
4. Replace physical layout assumptions with logical CSS and direction-aware
   markup, including mirrored icons and isolated user-authored text.
5. Migrate the frontend in dependency order, starting with schedule and booking
   surfaces and their dependent shared calendar/modal controls.
6. Keep untranslated admin-authored content, chat text, nicknames, and other
   user-generated content outside the catalog system unless a later phase owns
   explicit multilingual authoring for that data.
7. Add deterministic completeness checks for catalog parity and hard-coded
   literals as the migration expands.

## Rationale

The schedule and booking slice exercises the most important moving parts at
once: date formatting, drawer/modal layout, responsive controls, approval flows,
and both member and admin interactions. Treating the migration as a single
monolithic rewrite would increase risk and make verification harder, while
splitting it by feature slice preserves atomic commits and keeps translation
ownership obvious.

Stable catalog keys and ICU messages remain reviewable in source control, while
logical CSS and direction-aware markup reduce the number of one-off RTL fixes
needed later. Keeping user-generated text out of the catalog system avoids
mixing translation concerns with content ownership.

## Alternatives Considered

A broad table-driven translation database was rejected because it would reintroduce
runtime dependencies, blur ownership across contexts, and make offline/frontend
verification harder.

A single pass global replacement of every literal across the web app was
rejected because the blast radius would be too large to verify safely and would
hide which feature slices still needed RTL-specific validation.

Locale-prefixed routes were rejected for the authenticated application because
language preference is part of user settings rather than URL identity, and the
product already has stable operational routes.

## Consequences

The frontend now has an explicit phase boundary for catalog completeness work.
Each feature slice may introduce new catalog keys, formatter helpers, and RTL
layout fixes, but must remain dependency-ordered and paired with live
verification.

The migration will temporarily leave a mix of translated and untranslated
surfaces in the tree while the slices are completed. That is acceptable only
while the remaining work is tracked in the phase plan and subsequent ADR notes.

## Implementation Notes

Phase 2 completed the frontend-owned copy migration across public, member,
athlete, admin, workout-authoring, execution, finance, messaging, notification,
gamification, review, wellbeing, and transient loading/error surfaces. The final
catalog contains 1,938 messages in each of the twelve supported locales. The
inventory had to expand beyond JSX: workout format metadata, theme descriptions,
hook-generated errors, schedule namespace copy, and formatter helpers were also
runtime UI sources and are now catalog backed.

Implementation established three deterministic safeguards: exact key parity and
non-empty values for every locale, ICU placeholder-name parity, and a TypeScript
AST scan for hard-coded TSX display copy. The translation tooling protects ICU
parameters with numeric sentinels during translation; this was added after the
first automated pass revealed that translation providers may translate or drop
placeholder names.

Direction support was completed with logical Tailwind utilities and logical
inline CSS properties, mirrored navigation glyphs, direction-aware swipe
semantics, RTL drawer placement/shadows, and locale-aware date, time, weekday,
number, and currency formatting. Technical strings such as media queries, MIME
types, date-construction suffixes, storage keys, and API enums remain canonical
and are explicitly excluded from translation.

Live verification covered English and Greek LTR login flows, Arabic and Hebrew
RTL login flows, and authenticated admin/member/athlete pages using signed local
development access tokens. All checked pages rendered the expected `lang` and
`dir`, had no horizontal viewport overflow, and raised no browser page errors.
The local Argon2 NIF was unavailable, so authenticated verification used signed
development tokens rather than the password login endpoint; authorization and
real API reads remained active.

Backend error semantics, machine-enum presentation, push/service-worker payloads,
manifest metadata, and export-generated copy intentionally remain the Phase 3
boundary. User-authored names, workout content, notes, and chat messages remain
verbatim by design.
