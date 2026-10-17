import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

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
  },
  // ADR-137: member pages moved under their tab; old links keep working.
  // Temporary (307) while the redesign settles, so a later move is not cached.
  async redirects() {
    return MEMBER_ROUTE_MOVES.flatMap(([from, to]) => [
      { source: `${from}/:path*`, destination: `${to}/:path*`, permanent: false },
      {
        source: `/org/:organization_slug${from}/:path*`,
        destination: `/org/:organization_slug${to}/:path*`,
        permanent: false,
      },
    ]);
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
