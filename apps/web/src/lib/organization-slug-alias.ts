// ADR-104: retired organization slugs. The web proxy issues a 308 from
// `/org/<retired>/...` to `/org/<canonical>/...` after asking the API which
// canonical slug replaced a retired one. Lookups are best-effort: on any
// failure the request proceeds unchanged, and the API still resolves the
// retired slug transparently for tenant requests.

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ORGANIZATION_PATH = /^\/org\/([^/]+)(\/.*)?$/;
const CACHE_TTL_MS = 60_000;
const CACHE_MAX_ENTRIES = 500;
const LOOKUP_TIMEOUT_MS = 1_500;

type CacheEntry = { canonicalSlug: string | null; expiresAt: number };

export type SlugAliasLookupOptions = {
  apiOrigin?: string;
  fetchImpl?: typeof fetch;
  now?: () => number;
  cache?: Map<string, CacheEntry>;
};

// Best-effort per-instance memo; correctness never depends on it.
const defaultCache = new Map<string, CacheEntry>();

export function organizationPathSlug(pathname: string): string | null {
  const slug = pathname.match(ORGANIZATION_PATH)?.[1] ?? null;
  return slug && SLUG_PATTERN.test(slug) && slug.length >= 3 && slug.length <= 63 ? slug : null;
}

/** Same path and query under the canonical slug; everything after `/org/<slug>` is preserved. */
export function canonicalOrganizationUrl(url: URL, canonicalSlug: string): URL {
  const target = new URL(url.toString());
  const match = target.pathname.match(ORGANIZATION_PATH);
  target.pathname = `/org/${canonicalSlug}${match?.[2] ?? ""}`;
  return target;
}

export function apiOriginForProxy(env: Record<string, string | undefined> = process.env) {
  return (env.API_PROXY_TARGET ?? "http://127.0.0.1:4000").replace(/\/+$/, "");
}

export async function lookupCanonicalOrganizationSlug(
  slug: string,
  { apiOrigin = apiOriginForProxy(), fetchImpl = fetch, now = Date.now, cache = defaultCache }: SlugAliasLookupOptions = {},
): Promise<string | null> {
  const cached = cache.get(slug);
  if (cached && cached.expiresAt > now()) return cached.canonicalSlug;

  let canonicalSlug: string | null;

  try {
    const response = await fetchImpl(`${apiOrigin}/api/organization-slug-aliases/${encodeURIComponent(slug)}`, {
      headers: { accept: "application/json" },
      cache: "no-store",
      signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS),
    });

    if (response.status === 404) {
      canonicalSlug = null;
    } else if (response.ok) {
      const payload = (await response.json()) as { canonical_slug?: unknown };
      const candidate = payload.canonical_slug;
      canonicalSlug =
        typeof candidate === "string" && SLUG_PATTERN.test(candidate) && candidate !== slug ? candidate : null;
    } else {
      // Rate limited or unavailable: do not cache, do not redirect.
      return null;
    }
  } catch {
    return null;
  }

  if (cache.size >= CACHE_MAX_ENTRIES) cache.clear();
  cache.set(slug, { canonicalSlug, expiresAt: now() + CACHE_TTL_MS });
  return canonicalSlug;
}

/** The 308 target for a retired-slug request, or null when no redirect applies. */
export async function retiredOrganizationSlugRedirect(
  method: string,
  url: URL,
  options?: SlugAliasLookupOptions,
): Promise<URL | null> {
  if (method !== "GET" && method !== "HEAD") return null;

  const slug = organizationPathSlug(url.pathname);
  if (!slug) return null;

  const canonicalSlug = await lookupCanonicalOrganizationSlug(slug, options);
  return canonicalSlug ? canonicalOrganizationUrl(url, canonicalSlug) : null;
}
