import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

import { BUDDY_REDIRECTS } from "./src/components/buddy/buddy-links";
import { MEMBER_ROUTE_MOVES } from "./src/lib/member-routes";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const nextConfig: NextConfig = {
  output: "standalone",
  distDir: process.env.NEXT_DIST_DIR ?? ".next",
  turbopack: {
    root: process.cwd(),
  },
  typescript: {
    tsconfigPath: "tsconfig.next.json",
  },
  experimental: {
    // Dev-only /api rewrite: the workout assistant can take longer than the
    // 30 s default. Production routes /api straight to Phoenix via Caddy.
    proxyTimeout: 90_000,
    // Pages are client shells that fetch their own data, so a page's RSC
    // payload carries no user data and can be reused across navigations:
    // revisiting a page needs no server round trip (one less wait per tap
    // on high-latency mobile networks).
    staleTimes: {
      dynamic: 300,
    },
  },
  // ADR-164: the dev-only anatomy preview (`page.dev.tsx`) is a route in `next dev` only.
  pageExtensions: process.env.NODE_ENV === "production" ? ["tsx", "ts", "jsx", "js"] : ["dev.tsx", "tsx", "ts", "jsx", "js"],
  async headers() {
    // ADR-164: atlas files are versioned by folder (v1), so they never change in place.
    return [
      {
        source: "/anatomy/v1/:file*",
        headers: [{ key: "Cache-Control", value: "public, max-age=31536000, immutable" }],
      },
    ];
  },
  // ADR-137: member pages moved under their tab; old links keep working.
  // Temporary (307) while the redesign settles, so a later move is not cached.
  async redirects() {
    // ADR-160: the API's paths for buddy screens open the web's.
    const buddy = BUDDY_REDIRECTS.map((entry) => ({ ...entry, permanent: false }));
    return [...buddy, ...MEMBER_ROUTE_MOVES.flatMap(([from, to]) => [
      { source: `${from}/:path*`, destination: `${to}/:path*`, permanent: false },
      {
        source: `/org/:organization_slug${from}/:path*`,
        destination: `/org/:organization_slug${to}/:path*`,
        permanent: false,
      },
    ])];
  },
  async rewrites() {
    const proxyTarget = process.env.API_PROXY_TARGET ?? "http://127.0.0.1:4000";

    return [
      {
        source: "/org/:organization_slug/:path*",
        destination: "/:path*",
      },
      {
        source: "/api/:path*",
        destination: `${proxyTarget}/api/:path*`,
      },
    ];
  },
};

export default withNextIntl(nextConfig);
