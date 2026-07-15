# ADR-023: Dynamic Gamification Help Copy
Date: 2026-06-13
Status: Accepted

## Context

Admin gamification settings control the weekly workout target, streak shield
reset behavior, and leaderboard visibility. The admin settings screen explained
these settings in a separate static runtime behavior panel, while the landing
page help copy used hard-coded streak and consistency descriptions.

When admins change the weekly workout target, user-facing help must explain the
current target rather than stale defaults.

## Decision

The landing page payload will include the current Gamification settings under
`gamification.settings`. User-facing landing help copy will derive target-based
instructions from this read model.

The admin settings page will replace the separate runtime behavior panel with
per-field info controls that open contextual help on hover or click.

## Rationale

The backend already owns the settings and already invalidates landing caches
when settings change. Sending the setting values in the landing payload keeps
the frontend copy aligned with the same cached read model users already fetch,
without adding another request or duplicating setting state in the browser.

Per-field help keeps instructions next to the field being edited and reduces
screen clutter.

## Alternatives Considered

Keeping static landing copy:
rejected because it becomes misleading as soon as admins change the weekly
target.

Fetching admin settings separately on the landing page:
rejected because the landing page already has a cached authenticated payload and
settings are part of the gamification read model.

## Consequences

The landing OpenAPI contract includes `gamification.settings`. Landing cache
invalidation remains the mechanism that propagates admin setting changes to
user-facing instructions.

## Implementation Notes

Implemented on 2026-06-13.

`GetLandingPage` now includes `Gamification.get_settings()` under
`gamification.settings`, and the Landing controller spec documents the setting
shape. The landing frontend type and help modals use
`weekly_workout_target` to render streak and consistency explanations such as
“at least 3 workouts” after admins set the target to 3.

The admin settings page removed the runtime behavior panel and added clickable
and hoverable info controls for weekly workout target, streak shield reset day,
and global leaderboard visibility.

Verification completed with:

- `MIX_BUILD_PATH=/tmp/milos-api-build-test DB_PORT=5434 mix test test/milos_training_web/controllers/landing_controller_test.exs`
- `MIX_BUILD_PATH=/tmp/milos-api-build-dev mix compile --warnings-as-errors`
- `MIX_BUILD_PATH=/tmp/milos-api-build-dev mix milos.export_openapi ../web/src/api/generated/openapi.json`
- `npx openapi-typescript src/api/generated/openapi.json -o src/api/generated/schema.ts`
- `npx eslint src/components/admin-settings.tsx src/components/landing-page.tsx src/api/landing.ts`
- `npx tsc --noEmit`
- `npm run build`
