import type { MetadataRoute } from "next";

import { siteOrigin } from "@/lib/site-url";
import { PUBLIC_PAGES } from "@/lib/seo/site-info";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const origin = await siteOrigin();
  return [
    { url: new URL("/", origin).toString(), changeFrequency: "weekly", priority: 1 },
    ...PUBLIC_PAGES.map(({ path }) => ({
      url: new URL(path, origin).toString(),
      changeFrequency: "weekly" as const,
      priority: path === "/about" ? 0.9 : 0.6,
    })),
  ];
}
