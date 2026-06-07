import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  typescript: {
    tsconfigPath: "tsconfig.next.json",
  },
  async rewrites() {
    const proxyTarget = process.env.API_PROXY_TARGET ?? "http://127.0.0.1:4000";

    return [
      {
        source: "/api/:path*",
        destination: `${proxyTarget}/api/:path*`,
      },
    ];
  },
};

export default nextConfig;
