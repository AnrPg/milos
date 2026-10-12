import { NextRequest } from "next/server";
import { afterEach, describe, expect, test, vi } from "vitest";

import { config, configuredMediaOrigins, proxy } from "@/proxy";

describe("configuredMediaOrigins", () => {
  test("uses the explicit public media origin allowlist first", () => {
    expect(
      configuredMediaOrigins({
        NEXT_PUBLIC_MEDIA_ORIGIN: "https://s3-milos.4kq.net, http://media.localhost:18080",
        MINIO_PUBLIC_ENDPOINT: "https://ignored.example.net",
      })
    ).toBe("https://s3-milos.4kq.net http://media.localhost:18080");
  });

  test("falls back to the MinIO public endpoint for presigned uploads", () => {
    expect(
      configuredMediaOrigins({
        MINIO_PUBLIC_ENDPOINT: "https://s3-milos.4kq.net",
      })
    ).toBe("https://s3-milos.4kq.net");
  });

  test("rewrites tenant-prefixed RSC and prefetch requests too", () => {
    expect(config.matcher[0]).not.toHaveProperty("missing");
  });
});

describe("retired organization slugs (ADR-112)", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test("308-redirects /org/<retired>/... to the canonical slug, keeping path and query", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) =>
        String(input).endsWith("/api/organization-slug-aliases/proxy-old-gym")
          ? new Response(JSON.stringify({ canonical_slug: "proxy-new-gym" }), { status: 200 })
          : new Response(JSON.stringify({ code: "organization_slug_alias_not_found" }), { status: 404 }),
      ),
    );

    const response = await proxy(new NextRequest("https://gym.example/org/proxy-old-gym/admin/finance?member=7"));

    expect(response.status).toBe(308);
    expect(response.headers.get("location")).toBe("https://gym.example/org/proxy-new-gym/admin/finance?member=7");
  });

  test("rewrites a canonical slug as before", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ code: "organization_slug_alias_not_found" }), { status: 404 })),
    );

    const response = await proxy(new NextRequest("https://gym.example/org/proxy-current-gym/schedule"));

    expect(response.status).toBe(200);
    expect(response.headers.get("x-middleware-rewrite")).toBe("https://gym.example/schedule");
  });
});
