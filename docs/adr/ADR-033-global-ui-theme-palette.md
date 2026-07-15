# ADR-033: Global UI Theme Palette
Date: 2026-06-14
Status: Accepted

## Context
The app currently mixes hard-coded colors across workout previews, schedule popups,
calendar actions, and chat messages. That makes the UI inconsistent and makes
admin-selected gym branding difficult to apply across authenticated and public
surfaces.

The design doc calls for a minimal, colorful, mobile-first interface and leaves
the difficulty color palette as a design-phase item. Admin settings already
act as the global runtime configuration surface, but theme selection needs to
apply to every user, not only the admin browser.

## Decision
Persist a global `theme_slug` on the existing global settings record and expose
a public read endpoint for the active theme. The web app will define all theme
tokens centrally, apply the active theme through CSS custom properties, and use
shared helpers for workout type and scale-level color decisions.

## Rationale
Using CSS custom properties gives existing Tailwind/inline-style components a
single source of stylistic truth without requiring a full design-system rewrite.
The public read endpoint lets unauthenticated, member, athlete, and admin
screens converge on the same selected theme.

Keeping the value on the current global settings record is the smallest
additive persistence change. The field is not gamification-specific, but the
existing settings record is already the global admin settings model used at
runtime.

## Alternatives Considered
Hard-coding new colors in the affected components was rejected because it would
repeat the current inconsistency and would not support admin theme selection.

Local-storage-only theme selection was rejected because it would not apply to
the whole app for every user.

Creating a separate branding context was rejected for this change because the
current need is one constrained global setting, not a broader tenant-branding
domain.

## Consequences
Frontend components should import theme helpers or use CSS variables instead
of adding new hard-coded palette values.

The global settings API now carries a non-gamification field. If future
branding settings grow beyond theme selection, a dedicated settings/branding
context should replace this temporary co-location.

## Implementation Notes
Implemented `theme_slug` as an additive field on the existing global settings
record with accepted values `ember`, `sage`, and `steel`. The admin settings API
can read/write the field, and `/api/theme` exposes the active theme publicly so
all users can load the same palette without admin credentials.

The web app now defines theme tokens in `apps/web/src/lib/theme.ts`, applies
them from a root `ThemeProvider`, and maps legacy `workout-colors.ts` callers
to CSS variables. Schedule popup, workout preview scale chips/variation rows,
embedded chat, and direct messages now use theme variables instead of fixed
purple/blue or single-color variation styles.

OpenAPI JSON and the generated TypeScript schema were regenerated through the
project export path using a temporary Mix build directory because the default
`apps/api/_build/dev` dependency build was in a stale bad state.

Focused backend tests passed against the local Docker Postgres port. Full
frontend lint still fails on pre-existing unrelated finance/search/session
issues, while the Next build passed after these changes.
