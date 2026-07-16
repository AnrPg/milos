# Full Localization and RTL Rollout Plan

**Date:** 2026-07-16  
**Status:** In progress  
**Locales:** `en`, `el`, `ar`, `ru`, `de`, `es`, `pt-PT`, `he`, `it`, `bg`, `nl`, `fr`

## Goal

Translate all application-owned text, persist each user's language preference,
fully support Arabic and Hebrew RTL layouts, localize backend-originated copy,
and provide enforceable completeness and quality gates without introducing a
global runtime translation database.

Every phase follows this lifecycle in order:

1. Read the design document, implementation plan, relevant ADRs, and debt ledger.
2. Create and index the phase ADR before implementation.
3. Use failing tests before every non-trivial backend/domain function and add
   frontend contract/completeness tests before migrating production surfaces.
4. Implement in dependency order and run targeted then full verification.
5. Live-test all affected user flows and supported directions.
6. Revisit the phase ADR and record emergent decisions, deviations, constraints,
   verification, and deferrals.
7. Commit in small semantic dependency-ordered groups.
8. Request the required human confirmation immediately before pushing.

## Phase 1 — Locale and RTL Foundation

**ADR:** ADR-045  
**Outcome:** Locale follows the user across devices and the common application
shell can render catalog-backed text correctly in both LTR and RTL directions.

- Add Identity locale policy and a non-destructive `preferred_locale` migration.
- Extend User, Account, UserStore port/adapter, registration/auth/profile read
  models, and the contract-first current-user profile update endpoint.
- Add backend unit/integration/controller tests before implementation.
- Install and configure `next-intl` without locale-prefixed routes.
- Add the twelve ICU catalogs with typed locale metadata and English fallback.
- Resolve locale from user preference/cookie/browser/default and synchronize the
  cookie after authentication or preference change.
- Set dynamic root `lang`/`dir`, add RTL-safe base styles, and isolate mixed text.
- Add the personal-settings language selector.
- Migrate metadata, authentication, top navigation, profile, shared heroes,
  notification shell, and common controls to catalog keys.
- Verify migration, OpenAPI regeneration, backend tests, catalog validation,
  TypeScript, lint, production build, locale switching, persistence, and core
  desktop/mobile RTL flows.
- Update ADR-045, make atomic commits, and request confirmation before push.

## Phase 2 — Complete Frontend Catalog and RTL Migration

**ADR:** Create the next available ADR before code.  
**Outcome:** Every application-owned frontend string is catalog-backed in all
twelve locales and every role workflow remains usable in RTL.

- Produce a classified inventory: UI copy, enum labels, formatted values,
  backend errors, administrator content, and unstructured user text.
- Migrate feature slices in dependency/usage order: schedule and bookings;
  workout browsing/authoring/assignment; execution and offline states;
  landing/gamification/Pantheon; finance; coaching; reviews/wellbeing; messaging;
  admin users, analytics, marketing, settings, and empty/error/loading states.
- Replace manual date, time, duration, number, percent, list, ordinal, and currency
  output with locale-aware formatters while keeping timezone independent.
- Replace fragment concatenation with complete ICU messages and plural/select
  rules. Validate Arabic, Russian, Bulgarian, Greek, and Hebrew grammar shapes.
- Replace physical layout assumptions with logical CSS and audit directional
  icons, drawers, charts, tables, calendars, gestures, and animation origins.
- Add deterministic catalog parity, ICU syntax, unused-key, and forbidden
  hard-coded-literal checks with narrowly documented exceptions.
- Live-test member, athlete, and admin critical paths in English, Greek, Arabic,
  and Hebrew plus smoke checks for every other locale.
- Update the phase ADR, commit atomically, and request confirmation before push.

## Phase 3 — Backend Delivery, Dynamic Content, and Release Gates

**ADR:** Create the next available ADR before code.  
**Outcome:** Server-originated messages and selected administrator-authored
content are localized, and CI prevents localization regressions.

- Add/organize Phoenix Gettext domains and all twelve PO catalogs for push,
  notification snapshots, exports, and other server-rendered user copy.
- Carry recipient locale through durable notification jobs and persist rendered
  locale/snapshots where historical fidelity is required.
- Define stable semantic API error codes and arguments contract-first; translate
  them in the browser while retaining safe backend fallback messages.
- Decide from the Phase 2 inventory which administrator-authored aggregates
  require multilingual variants. Add only context-owned translation schemas,
  commands, queries, public APIs, application orchestration, OpenAPI contracts,
  and authoring/fallback UI for those approved fields.
- Never auto-translate chat, notes, nicknames, or athlete free text; apply
  direction isolation to their display.
- Add glossary, translator notes, review status, missing-translation reports,
  pseudo-localization, text-expansion tests, and automated RTL screenshots.
- Add CI gates for frontend/backend catalog completeness, ICU/Gettext validity,
  stable error-code coverage, and hard-coded UI copy.
- Run the full backend/web/precommit suites and live tests for push, offline
  execution, all role flows, all locales, RTL, keyboard access, and WCAG AA.
- Update the phase ADR and technical debt ledger, commit atomically, request push
  confirmation, then push after approval.

## Intended Commit Sequence Per Phase

1. `docs(adr): ... — record constraints before implementation`
2. `test(identity|i18n|...): ... — define the behavior contract`
3. `feat(identity): ... — persist or expose locale state`
4. `docs(openapi): ... — publish the locale/error/content contract`
5. `chore(web): ... — establish localization tooling`
6. `feat(i18n): ... — migrate one coherent UI/backend slice`
7. `fix(rtl): ... — correct one verified directional behavior`
8. `test(i18n): ... — enforce completeness and prevent regression`
9. `docs(adr): ... — record implementation evidence and deferrals`

Tests remain with the implementation they validate when that produces the most
atomic commit; the ordering above describes dependencies, not a requirement to
separate every test from its behavior.
