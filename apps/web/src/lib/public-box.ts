import { cache } from "react";

import type { PublicBoxPage } from "@/api/social";
import { apiOriginForProxy } from "@/lib/organization-slug-alias";

/** The product name on link previews of gyms without a page. */
export const BRAND_NAME = "Palee";

/**
 * Server-side read of a published box page (ADR-142) for `/b/[slug]`, its
 * metadata and its link preview. Null when no published gym has this slug.
 * Memoised per request so the page and its metadata share one fetch.
 */
export const loadPublicBox = cache(async (slug: string): Promise<PublicBoxPage | null> => {
  const response = await fetch(`${apiOriginForProxy()}/api/public/boxes/${encodeURIComponent(slug)}`, {
    headers: { accept: "application/json" },
    next: { revalidate: 60 },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`public box ${slug}: ${response.status}`);
  return (await response.json()) as PublicBoxPage;
});

/** «discipline · neighbourhood» for previews and the page description (board 4 Q14). */
export function previewLine(page: PublicBoxPage, discipline: (key: string) => string) {
  const first = page.profile.disciplines[0];
  const place = page.locations.find((location) => location.neighbourhood || location.city);
  return [first ? discipline(first) : null, place?.neighbourhood ?? place?.city ?? null].filter(Boolean).join(" · ");
}
