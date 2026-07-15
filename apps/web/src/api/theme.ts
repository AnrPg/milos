import { apiRequest } from "@/api/client";
import type { ThemeSlug } from "@/lib/theme";

export type PublicThemePayload = {
  theme_slug: ThemeSlug;
};

export async function fetchPublicTheme() {
  return apiRequest<PublicThemePayload>("/theme");
}
