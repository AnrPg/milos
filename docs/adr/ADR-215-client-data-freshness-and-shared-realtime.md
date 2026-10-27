# ADR-215: Client data freshness by kind, and one shared realtime connection
Date: 2026-10-27
Status: Accepted

## Context
The network panel showed the same ~13 requests (memberships ×2, both unread
counts, clubs, setup checklist, demo status, password resets, the last 20
notifications, branches, staff) on every return to the tab of a staff page.
Causes found in the web client:

- every query was stale after 15 s and refetched on window focus;
- shell parts (TopNav, bell, guides, onboarding) fetched data for badges and
  popups that are usually hidden, the bell a full page of notifications for
  its count;
- memberships were cached under four keys, one holding the access token, and
  about 20 query keys held the token, so every 15-minute renewal refetched
  them and showed their screens loading again;
- `lib/realtime` kept one socket and replaced it whenever the token or the
  tenant context differed between subscribers (a page with user-wide and gym
  topics flapped), and two subscribers of one topic joined it twice, so the
  server closed the older channel. Live events were lost, which is why
  messages, buddies and partners also polled every 2 minutes.

## Decision
1. **Freshness by kind** (`lib/query-policy.ts`): `account` 10 min,
   `reference` 5 min, `pushed` 5 min (kept current by realtime events),
   `live` 60 s (the default). Focus refetch stays on, so only stale data of
   the screens on show refetches.
2. **One cache entry per piece of data, named by the data**: no token in a
   query key; memberships through `useOrganizationMemberships` only. The
   session empties the query cache when the signed-in person changes or
   signs out, so keys need no user part to stay private.
3. **Shell data where it shows**: clubs load for guides only during a guide
   run or on guide screens; the bell reads `GET /api/notifications/unread-count`
   and loads its list only while open.
4. **Realtime**: one socket for the person and one per gym for tenant
   topics, each kept across token renewals (params are read at each
   reconnect); one channel per topic shared by all subscribers; `onRejoin`
   tells subscribers to resync after a reconnect. Realtime-backed queries poll
   (`useRealtimeFallbackInterval`) only while the person's socket is down.

## Rationale
Push plus a resync on reconnect keeps data current without polling; freshness
by kind removes the focus storm without hiding real changes, since actions and
events invalidate what they change.

## Alternatives Considered
- Turning focus refetch off globally: stale page data after long absences.
- One socket carrying the gym context for every topic: a gym the token no
  longer allows would refuse the whole connection, user-wide topics included.

## Consequences
New shell queries pick a `FRESHNESS` kind and are enabled only where shown.
Query keys never include the token. Polls that remain are page-scoped work
queues without realtime (password resets 30 s, reply queue and shop order
60 s, the visitor's box chat 5 s).
