import type { OnDemandVideo } from "@/api/content";

/** The video's link when it is a well-formed HTTPS URL; anything else is not opened. */
export function safeVideoUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url.trim());
    return parsed.protocol === "https:" && parsed.hostname ? parsed.toString() : null;
  } catch {
    return null;
  }
}

/** Short host name shown on the card (`youtube.com`, `vimeo.com`, …). */
export function videoHost(url: string | null | undefined): string | null {
  const safe = safeVideoUrl(url);
  if (!safe) return null;
  const host = new URL(safe).hostname.replace(/^(www\.|m\.)/, "");
  return host === "youtu.be" ? "youtube.com" : host;
}

/** Every tag used by the videos, de-duplicated case-insensitively and sorted. */
export function videoTags(videos: OnDemandVideo[], locale?: string): string[] {
  const tags = new Map<string, string>();
  for (const video of videos) {
    for (const tag of video.tags) {
      const trimmed = tag.trim();
      if (trimmed && !tags.has(trimmed.toLocaleLowerCase())) {
        tags.set(trimmed.toLocaleLowerCase(), trimmed);
      }
    }
  }
  return [...tags.values()].sort((a, b) => a.localeCompare(b, locale));
}

/** The videos with any of `tags` (case-insensitive); every video when none is picked. */
export function filterVideosByTag(videos: OnDemandVideo[], tags: readonly string[]): OnDemandVideo[] {
  if (tags.length === 0) return videos;
  const needles = new Set(tags.map((tag) => tag.toLocaleLowerCase()));
  return videos.filter((video) => video.tags.some((value) => needles.has(value.trim().toLocaleLowerCase())));
}
