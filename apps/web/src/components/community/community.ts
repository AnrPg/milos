import type { CommunityChannel, CommunityClub, CommunityPost } from "@/api/community";

/**
 * Pure helpers for the club bar, the feed and compose (ADR-138). Built-in
 * channels carry no stored name; the client names them by kind.
 */
const BUILT_IN = new Set(["announcements", "wod", "challenges"]);

/** The translation key of a channel's name, or null when it has its own. */
type ChannelNaming = { kind?: CommunityChannel["kind"] | string | null; name?: string | null };

export function channelNameKey(channel: ChannelNaming): string | null {
  if (!channel.kind) return null;
  if (channel.name && !BUILT_IN.has(channel.kind)) return null;
  return `channel.${channel.kind}`;
}

export function channelName(channel: ChannelNaming, t: (key: string) => string): string {
  const key = channelNameKey(channel);
  return key ? t(key) : (channel.name ?? "");
}

/** Up to two letters for a club's avatar. */
export function clubInitials(name: string): string {
  const words = name
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter(Boolean);
  const letters = words.length > 1 ? words[0][0] + words[1][0] : (words[0] ?? "?").slice(0, 2);
  return letters.toLocaleUpperCase();
}

/** Every channel the member may post in, as compose lists them: club › #channel. */
export function postableChannels(clubs: CommunityClub[]) {
  return clubs.flatMap((club) =>
    club.channels.filter((channel) => channel.can_post).map((channel) => ({ club, channel })),
  );
}

/** The default compose target: the club's #wod-σήμερα, else its first writable channel. */
export function defaultChannelId(clubs: CommunityClub[], clubId?: string | null): string | null {
  const options = postableChannels(clubs).filter((option) => !clubId || option.club.id === clubId);
  return (options.find((option) => option.channel.kind === "wod") ?? options[0])?.channel.id ?? null;
}

/** Drops pinned posts from the page list so a pinned post shows once. */
export function withoutPinned(posts: CommunityPost[], pinned: CommunityPost[]): CommunityPost[] {
  const ids = new Set(pinned.map((post) => post.id));
  return posts.filter((post) => !ids.has(post.id));
}

/** A new client operation id, so a retried publish never posts twice. */
export function newOperationId(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? `post-${crypto.randomUUID()}`
    : `post-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/** The post attachment type of a journal entry kind; null when it cannot be shared. */
export function attachmentTypeOf(kind: string): "workout_execution" | "training_log_entry" | "pr" | null {
  if (kind === "execution") return "workout_execution";
  if (kind === "training_log") return "training_log_entry";
  if (kind === "pr") return "pr";
  return null;
}
