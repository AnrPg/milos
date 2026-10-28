/**
 * How long each kind of server data stays fresh in the client cache. A fresh
 * query is served from the cache on mount, navigation and return to the
 * tab; a stale one refetches then. The kinds:
 *
 * - `account`: who the person is and where they belong (memberships, roles,
 *   gyms, setup checklist). Changes only through actions that invalidate it
 *   or through a realtime `sync` event.
 * - `reference`: settings and catalogues a screen reads (branches, staff,
 *   spaces, class types).
 * - `pushed`: kept current by realtime events (unread counts, notifications);
 *   the fetch is only a resync, done again after a reconnect.
 * - `live`: lists people act on; the default for every other query.
 */
export const FRESHNESS = {
  account: 10 * 60_000,
  reference: 5 * 60_000,
  pushed: 5 * 60_000,
  live: 60_000,
} as const;

/** Safety-net polling for realtime-backed data, used only while the live connection is down. */
export const REALTIME_FALLBACK_REFETCH_MS = 2 * 60_000;
