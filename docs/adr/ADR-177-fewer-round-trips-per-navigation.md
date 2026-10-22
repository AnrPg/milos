# ADR-177: Fewer round trips per navigation
Date: 2026-10-22
Status: Accepted

## Context
Production felt slow on phones even though the API answers in 7–60 ms. Every step was a sequential network round trip, and each costs 100–300 ms on mobile:

- Opening the app: HTML → JS → `POST /auth/refresh` → `GET /auth/me` → memberships → page data.
- Every tap: the router fetched the new page's RSC payload, because `staleTimes.dynamic` defaults to 0 and nav links did not prefetch dynamic routes. Only then did it load code and fetch data.
- Every full page load inlined the whole message catalogue in the HTML: about 450 KB in English and 700 KB in Greek, uncacheable.

## Decision
1. **Session with the user.** `POST /auth/login` and `POST /auth/refresh` return `user` (the `/auth/me` payload) next to `access_token`. The web session uses it and only falls back to `/auth/me` when it is missing (registration).
2. **Client cache for pages.** `experimental.staleTimes.dynamic = 300`. Pages are client shells that fetch their own data with the user's token, so a page's RSC payload carries no user data and is safe to reuse.
3. **Prefetch.** Bar, tab and menu links use `prefetch` (full). `ScreenPreloader` prefetches the role's likely screens when the browser is idle after sign-in. `likelyScreens()` returns the bar links plus the most used sub-pages, at least six where the role has that many.
4. **Catalogue as a cached chunk.** `ClientMessagesProvider` imports `messages/<locale>.json` dynamically. Webpack emits one content-hashed chunk per locale, served `immutable` from `/_next/static`. The layout passes only `locale` and `timeZone`. Server components keep using `getTranslations`.

## Rationale
Each change removes a sequential wait without moving data fetching to the server or weakening auth: tokens stay in memory and pages stay client-rendered.

## Alternatives Considered
- **Passing only the namespaces client components use.** Rejected: most strings live in the shared `Ui` namespace, so the saving would be small.
- **Server-side data fetching per page.** Rejected: it would need the access token on the server (a cookie), which is a larger auth change.

## Consequences
- On a first visit, hydration waits for the catalogue chunk. Later visits read it from the browser cache.
- A deploy that changes a page leaves already-open tabs using the cached payload for up to 5 minutes. The data is still fresh because React Query owns it.
