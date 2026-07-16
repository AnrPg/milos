# ADR-045: Hybrid localization and RTL foundation
Date: 2026-07-16
Status: Accepted

## Context

Milos Training must support English, Greek, Arabic, Russian, German, Spanish,
Portuguese, Hebrew, Italian, Bulgarian, Dutch, and French. Users choose their
language from personal settings. The application contains several distinct
classes of text: versioned interface copy, backend-originated notification and
export copy, administrator-authored domain content, and unstructured user text.
Treating all of these as columns in one database translation table would make
runtime UI availability depend on PostgreSQL, handle plural grammar poorly,
require migrations for new locales, and create a cross-context persistence
owner that conflicts with bounded-context rules.

Arabic and Hebrew also require structural right-to-left behavior rather than
word substitution alone. The current web root fixes `lang="en"`, many React
surfaces contain literal English, and Identity does not persist a locale.

## Decision

Adopt a hybrid localization architecture:

1. Identity owns a validated `preferred_locale` user preference. Authenticated
   preference is authoritative; a same-site locale cookie supports initial
   server rendering and signed-out/public pages; browser language negotiation
   is used only when neither exists; English is the final fallback.
2. The Next.js application uses `next-intl`, version-controlled ICU JSON
   catalogs, stable semantic message identifiers, and locale-aware date,
   number, currency, list, and plural formatting. Locale-prefixed routes are
   intentionally not introduced for the authenticated application.
3. The Phoenix application uses its existing Gettext support for text that the
   server must render, including Web Push, exports, and future email. API errors
   progressively expose stable semantic codes for frontend translation.
4. Administrator-authored content is translated only when the product requires
   multilingual authoring. Such translations remain in tables owned by the
   relevant bounded context; no universal cross-context translations table is
   introduced. Unstructured user text is displayed as authored.
5. `html[lang]` and `html[dir]` are set from the resolved locale. Arabic and
   Hebrew use RTL. Layout CSS migrates to logical direction, and mixed or
   user-authored strings use direction isolation (`dir="auto"` or `bdi`) where
   appropriate.
6. The rollout is divided into three phases. Every phase begins with its own ADR
   and ends by updating that ADR's Implementation Notes after tests and live
   verification.

Supported initial locale identifiers are `en`, `el`, `ar`, `ru`, `de`, `es`,
`pt-PT`, `he`, `it`, `bg`, `nl`, and `fr`. European Portuguese is selected for
the initial `pt-PT` catalog; Brazilian Portuguese can be added as an independent
locale without schema changes.

## Rationale

Versioned catalogs make application copy reviewable with the code that consumes
it, allow static completeness checks, and remain available during offline
workout execution. ICU syntax handles the substantially different plural rules
of the supported languages. Gettext provides equivalent backend extraction and
plural support without forcing Phoenix to load frontend artifacts.

Persisting only locale preference in Identity keeps the setting available on
every device while the cookie prevents an English flash before the authenticated
session is restored. Context-owned dynamic translations preserve aggregate
ownership and allow each domain to decide whether translated authoring is
actually meaningful.

## Alternatives Considered

A wide database row with one column per language was rejected because every
locale addition would require a migration, missing values would be sparse, and
plural/select variants would have no safe structure.

A normalized global `translation_keys` / `translation_values` runtime catalog
was rejected for application UI because it adds request-time infrastructure and
offline synchronization while creating ambiguous ownership across contexts. It
remains a possible publishing source only if a future self-hosted translation
console is required.

Using Gettext for both Phoenix and React was rejected because the React App
Router integration and ICU component formatting would require custom tooling.
Using only frontend catalogs was rejected because background push and exports
must be rendered when no browser runtime is present.

Locale-prefixed routes were rejected for the initial authenticated product
because language is a personal setting and stable operational URLs are more
valuable than localized route SEO. Public marketing routes may adopt locale
segments in a later ADR.

## Consequences

The web application gains one approved runtime dependency and twelve maintained
catalogs. Message keys become part of the reviewed interface contract. Identity
gains a non-destructive migration and profile contract extension. Backend and
frontend catalogs intentionally cover different message ownership rather than
pretending to be one shared runtime store.

RTL readiness requires layout work beyond message extraction. New UI must use
logical alignment and spacing, and CI will eventually reject missing catalogs
and untranslated interface literals. Translation quality requires a shared
fitness/finance/safety glossary and fluent review; generated translations are
drafts until reviewed.

## Implementation Notes

Phase 1 was closed out with the shared shell fully localized and the remaining
top-navigation work intentionally absorbed into the same navigation slice after
human approval. That kept the shell cohesive and avoided leaving a partially
translated role switcher or menu fragment behind while Phase 2 picks up the
feature-specific surfaces.

Phase 1 established the locale foundation without introducing a shared runtime
translation table. Identity now validates the fixed initial locale set in a
pure domain module and persists `preferred_locale` with an `en` default and a
matching PostgreSQL check constraint. The current-user auth and profile
contracts expose the preference, and profile updates reject unsupported locale
identifiers. `pt-PT` remains the only Portuguese locale in this rollout;
`pt-BR` is intentionally not treated as an alias for a stored preference.

The web application now resolves server-rendered locale in this order: locale
cookie, `Accept-Language`, then English. Once an authenticated user is known,
their persisted preference synchronizes the cookie and document direction. A
settings change writes through the profile API before reloading, which avoids a
locale URL scheme and ensures the next server render uses the new catalog.

`next-intl` loads twelve version-controlled ICU JSON catalogs. A deterministic
validation script checks catalog presence, key parity, and non-empty values;
Phase 1 contains 37 shared-shell, navigation, profile, and session messages in
each catalog. The root document sets `lang` and `dir`, Arabic and Hebrew resolve
to RTL, shared navigation uses logical CSS properties, directional disclosure
icons mirror in RTL, and user-authored text has a base direction-isolation
style. Remaining feature-specific literal extraction and layout conversion are
the planned scope of Phase 2, not a Phase 1 deferral.

The implementation added an environment-selectable Next.js build directory so
production verification can run independently of the root-owned Docker
development cache. No runtime behavior changes when the variable is absent.

Verification completed on 2026-07-16:

- the locale domain, auth controller, and profile controller tests passed (23
  targeted tests), and the API compiled with warnings treated as errors;
- all twelve catalogs passed the 37-key parity check, targeted ESLint and both
  TypeScript configurations passed, and a clean production build completed;
- the development migration applied successfully, including the database
  locale constraint;
- a live API flow confirmed the default locale, persisted an Arabic profile
  update, and returned it from a fresh current-user request;
- a live browser flow confirmed Arabic `lang=ar` / `dir=rtl`, localized shared
  navigation, the profile language selector, and persistence through a switch
  to Greek with `lang=el` / `dir=ltr` after reload.

No new technical debt was recorded for Phase 1. Translation copy is an initial
product draft and remains subject to the glossary and fluent-review gates
already scheduled for Phase 3.
