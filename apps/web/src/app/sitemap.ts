import type { MetadataRoute } from "next";

import { siteOrigin } from "@/lib/site-url";

// The pages anyone can open without signing in.
const PUBLIC_PATHS = ["/", "/about", "/login", "/register", "/register/business"] as const;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const origin = await siteOrigin();
  return PUBLIC_PATHS.map((path) => ({
    url: new URL(path, origin).toString(),
    changeFrequency: "weekly",
    priority: path === "/" ? 1 : 0.6,
  }));
}
