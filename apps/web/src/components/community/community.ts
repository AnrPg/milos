import type { CommunityChannel, CommunityClub, CommunityPost } from "@/api/community";

/**
 * Pure helpers for the club bar, the feed and compose (ADR-138). Built-in
 * channels carry no stored name; the client names them by kind.
 */
const BUILT_IN = new Set(["announcements", "wod", "challenges", "general"]);

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

/**
 * Where a post goes (ADR-142, plan §5a Q13): a club channel (staff may also
 * make it public on the box page), or the member's own profile for their
 * followers or for everyone.
 */
export type ComposeTarget =
  | { kind: "channel"; channelId: string; public: boolean }
  | { kind: "profile"; audience: "followers" | "public" };

/** Every target the sheet offers: channels grouped by club, then the profile audiences. */
export function composeTargetGroups(clubs: CommunityClub[]) {
  return clubs
    .map((club) => {
      const channels = club.channels.filter((channel) => channel.can_post);
      const publicChannel = club.role === "staff" ? (channels.find((c) => c.kind === "announcements") ?? channels[0]) : undefined;
      return { club, channels, publicChannel };
    })
    .filter((group) => group.channels.length > 0);
}

export function sameTarget(a: ComposeTarget, b: ComposeTarget) {
  if (a.kind === "channel" && b.kind === "channel") return a.channelId === b.channelId && a.public === b.public;
  if (a.kind === "profile" && b.kind === "profile") return a.audience === b.audience;
  return false;
}

/**
 * The channel being read when the member may post there, else the remembered
 * target when it is still offered, else the club's default channel, else
 * followers.
 */
export function initialComposeTarget(
  clubs: CommunityClub[],
  remembered: ComposeTarget | null,
  clubId?: string | null,
  channelId?: string | null,
): ComposeTarget {
  if (channelId && postableChannels(clubs).some((option) => option.channel.id === channelId)) {
    return { kind: "channel", channelId, public: false };
  }
  const groups = composeTargetGroups(clubs);
  const offered = (target: ComposeTarget) =>
    target.kind === "profile" ||
    groups.some((group) =>
      target.public
        ? group.publicChannel?.id === target.channelId
        : group.channels.some((channel) => channel.id === target.channelId),
    );
  if (!clubId && remembered && offered(remembered)) return remembered;
  const fallback = defaultChannelId(clubs, clubId);
  return fallback ? { kind: "channel", channelId: fallback, public: false } : { kind: "profile", audience: "followers" };
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

/** The club of the member's selected gym, else their first gym club. */
export function gymClubFor(clubs: CommunityClub[], organizationId: string | null | undefined) {
  const gyms = clubs.filter((club) => club.kind === "gym");
  return gyms.find((club) => club.organization_id === organizationId) ?? gyms[0] ?? null;
}

/** The club's channel of one built-in kind. */
export function builtInChannel(club: CommunityClub | null, kind: "announcements" | "wod" | "challenges") {
  return club?.channels.find((channel) => channel.kind === kind) ?? null;
}

/**
 * Channels grouped as the club page lists them: the box's own, then class
 * groups, then the rest. Member groups (board 7 Q2) and PT squads (ADR-168)
 * have their own cards.
 */
export function channelSections(channels: CommunityChannel[]) {
  const box = channels.filter((channel) => BUILT_IN.has(channel.kind));
  const classes = channels
    .filter((channel) => channel.kind === "class_slot")
    .sort((a, b) => Number(Boolean(b.suggested)) - Number(Boolean(a.suggested)) || (a.name ?? "").localeCompare(b.name ?? ""));
  const other = channels.filter(
    (channel) =>
      !BUILT_IN.has(channel.kind) && channel.kind !== "class_slot" && channel.kind !== "member_group" && channel.kind !== "pt_squad",
  );
  return { box, classes, other };
}
