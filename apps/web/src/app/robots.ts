import type { MetadataRoute } from "next";

import { siteOrigin } from "@/lib/site-url";

// Crawlers may index the public pages; everything behind sign-in answers with
// the login screen anyway, so only the API and internal routes are excluded.
export default async function robots(): Promise<MetadataRoute.Robots> {
  const origin = await siteOrigin();
  return {
    rules: [{ userAgent: "*", allow: "/", disallow: ["/api/", "/socket/", "/dev/", "/platform/"] }],
    sitemap: new URL("/sitemap.xml", origin).toString(),
    host: origin.host,
  };
}
