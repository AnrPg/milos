# ADR-117: Web Dependency Security Refresh and Patched OpenAPI Generator Chain
Date: 2026-10-12
Status: Accepted

## Context
TD-042 deferred a dev-only `js-yaml` advisory reachable through
`openapi-typescript` → `@redocly/openapi-core`: forcing a patched `js-yaml`
broke OpenAPI generation, so the decision was to wait for an
upstream-compatible release. By 2026-10-12 the full audit also reported new
production advisories, including a **critical Next.js unauthenticated remote
code execution** affecting `next` 16.0.0–16.3.7. The CI release gate
(`npm audit --omit=dev --audit-level=high`) was therefore failing.

## Decision
- Bump the pinned `next` and `eslint-config-next` from 16.3.0 to the 16.3.8
  patch release, the smallest version outside the advisory range.
- Move the Tiptap family together to `^3.31.4`. Its packages use exact peer
  versions, so they cannot be upgraded one at a time. This also picks up the
  `prosemirror-view` XSS fix.
- Apply in-range updates for `dompurify`, `phoenix` (JS client), `undici`,
  `browserslist`, `baseline-browser-mapping`, `source-map-js`, and
  `brace-expansion`.
- Resolve TD-042 by updating the transitive `@redocly/openapi-core` to
  1.34.20, which ships patched `js-yaml` 4.3.2 within `openapi-typescript`
  7.13.0's existing range. Regenerated output is byte-identical.
- Update `vitest` to `^4.1.11`, and declare `@testing-library/dom` (^10.4.1)
  explicitly as the peer `@testing-library/react` 16 requires. It was
  previously only auto-installed, so this adds no new package.

## Rationale
Patch and in-range upgrades fix every production advisory without changing
APIs. Upgrading the generator's own dependency chain is the upstream-compatible
path TD-042 was waiting for, without overriding `js-yaml` under a library that
pins it.

## Alternatives Considered
- `npm audit fix --force`: rejected; it proposes downgrading
  `eslint-config-next` to 14.x.
- An `overrides` entry for `js-yaml`: unnecessary now that upstream ships the
  patched version.

## Consequences
- `npm audit --omit=dev --audit-level=high` passes again.
- The full audit still reports 5 high, dev-only findings in the
  `braces` → `micromatch` → `fast-glob` chain under the Next ESLint tooling.
  No patched `braces` release exists (the advisory covers every version), so
  these are logged as TD-080 rather than forced.

## Implementation Notes
- npm 10.9.4 crashes (`Cannot read properties of null (reading 'edgesOut')`)
  resolving `vitest`'s optional `jsdom` peer. The lockfile was produced by
  removing the stale vitest entries and reinstalling with
  `--legacy-peer-deps`. A plain `npm ci` from the committed lockfile succeeds,
  which is what CI runs.
- Verified with: clean `npm ci`, lint (0 errors), type-check, 260 vitest
  tests, i18n check, a regenerated contract with no diff, `next build`, and
  all 14 Playwright e2e tests (chromium and mobile-chrome).
