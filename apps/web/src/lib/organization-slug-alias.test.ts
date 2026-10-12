import { describe, expect, test, vi } from "vitest";

import {
  apiOriginForProxy,
  canonicalOrganizationUrl,
  lookupCanonicalOrganizationSlug,
  organizationPathSlug,
  retiredOrganizationSlugRedirect,
} from "@/lib/organization-slug-alias";

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function aliasFetch(map: Record<string, string>) {
  return vi.fn(async (input: RequestInfo | URL) => {
    const slug = decodeURIComponent(String(input).split("/").pop() ?? "");
    return map[slug]
      ? jsonResponse(200, { slug, canonical_slug: map[slug], canonical_path: `/org/${map[slug]}` })
      : jsonResponse(404, { code: "organization_slug_alias_not_found" });
  });
}

describe("organizationPathSlug", () => {
  test("extracts a valid slug from tenant paths only", () => {
    expect(organizationPathSlug("/org/harbor-gym/admin/finance")).toBe("harbor-gym");
    expect(organizationPathSlug("/org/harbor-gym")).toBe("harbor-gym");
    expect(organizationPathSlug("/admin")).toBeNull();
    expect(organizationPathSlug("/org/Harbor%20Gym/admin")).toBeNull();
    expect(organizationPathSlug("/org/ab/admin")).toBeNull();
  });
});

describe("canonicalOrganizationUrl", () => {
  test("swaps only the slug, keeping the rest of the path and the query", () => {
    const target = canonicalOrganizationUrl(
      new URL("https://gym.example/org/harbor-gym/admin/finance?member=42&tab=invoices"),
      "north-harbor",
    );

    expect(target.toString()).toBe("https://gym.example/org/north-harbor/admin/finance?member=42&tab=invoices");
  });

  test("handles the bare organization path", () => {
    expect(canonicalOrganizationUrl(new URL("https://gym.example/org/harbor-gym"), "north-harbor").pathname).toBe(
      "/org/north-harbor",
    );
  });
});

describe("lookupCanonicalOrganizationSlug", () => {
  test("asks the API alias endpoint and caches both answers", async () => {
    const fetchImpl = aliasFetch({ "harbor-gym": "north-harbor" });
    const cache = new Map();
    const options = { apiOrigin: "http://api:4000", fetchImpl, cache, now: () => 1_000 };

    await expect(lookupCanonicalOrganizationSlug("harbor-gym", options)).resolves.toBe("north-harbor");
    await expect(lookupCanonicalOrganizationSlug("harbor-gym", options)).resolves.toBe("north-harbor");
    await expect(lookupCanonicalOrganizationSlug("north-harbor", options)).resolves.toBeNull();
    await expect(lookupCanonicalOrganizationSlug("north-harbor", options)).resolves.toBeNull();

    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(String(fetchImpl.mock.calls[0][0])).toBe("http://api:4000/api/organization-slug-aliases/harbor-gym");
  });

  test("expires cached answers", async () => {
    const fetchImpl = aliasFetch({ "harbor-gym": "north-harbor" });
    const cache = new Map();
    let clock = 0;
    const options = { apiOrigin: "http://api:4000", fetchImpl, cache, now: () => clock };

    await lookupCanonicalOrganizationSlug("harbor-gym", options);
    clock = 61_000;
    await lookupCanonicalOrganizationSlug("harbor-gym", options);

    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  test("fails open without caching when the API is unavailable or rate limited", async () => {
    const cache = new Map();
    const unavailable = vi.fn(async () => jsonResponse(429, { code: "rate_limited" }));
    const broken = vi.fn(async () => {
      throw new Error("connection refused");
    });

    await expect(lookupCanonicalOrganizationSlug("harbor-gym", { fetchImpl: unavailable, cache })).resolves.toBeNull();
    await expect(lookupCanonicalOrganizationSlug("harbor-gym", { fetchImpl: broken, cache })).resolves.toBeNull();
    expect(cache.size).toBe(0);
  });

  test("ignores malformed canonical slugs", async () => {
    const fetchImpl = vi.fn(async () => jsonResponse(200, { canonical_slug: "https://evil.example" }));

    await expect(
      lookupCanonicalOrganizationSlug("harbor-gym", { fetchImpl, cache: new Map() }),
    ).resolves.toBeNull();
  });
});

describe("retiredOrganizationSlugRedirect", () => {
  const options = () => ({ fetchImpl: aliasFetch({ "harbor-gym": "north-harbor" }), cache: new Map() });

  test("targets the canonical slug for GET and HEAD on a retired slug", async () => {
    const url = new URL("https://gym.example/org/harbor-gym/schedule?week=2026-10-12");

    await expect(retiredOrganizationSlugRedirect("GET", url, options())).resolves.toEqual(
      new URL("https://gym.example/org/north-harbor/schedule?week=2026-10-12"),
    );
    await expect(retiredOrganizationSlugRedirect("HEAD", url, options())).resolves.not.toBeNull();
  });

  test("does nothing for canonical slugs, non-tenant paths and writes", async () => {
    await expect(
      retiredOrganizationSlugRedirect("GET", new URL("https://gym.example/org/north-harbor/admin"), options()),
    ).resolves.toBeNull();
    await expect(
      retiredOrganizationSlugRedirect("GET", new URL("https://gym.example/today"), options()),
    ).resolves.toBeNull();
    await expect(
      retiredOrganizationSlugRedirect("POST", new URL("https://gym.example/org/harbor-gym/admin"), options()),
    ).resolves.toBeNull();
  });
});

test("apiOriginForProxy uses the same API_PROXY_TARGET as the Next rewrites", () => {
  expect(apiOriginForProxy({ API_PROXY_TARGET: "http://api:4000/" })).toBe("http://api:4000");
  expect(apiOriginForProxy({})).toBe("http://127.0.0.1:4000");
});
