import type { CommunityPost } from "@/api/community";
import type { FollowGroups, FollowStatus, PeopleRelation, PersonProfile } from "@/api/social";
import { PEOPLE_SEARCH_MIN } from "@/api/social";
import { formatDuration } from "@/lib/post-media";

/**
 * Pure rules for ADR-193's social web UI: the counts line, the Connections
 * tabs, the relation shown on a search result, the lock on a person's posts
 * and the follow notifications.
 */

export const CONNECTIONS_TABS = ["buddies", "followers", "following", "boxes", "clubs", "prs"] as const;
export type ConnectionsTab = (typeof CONNECTIONS_TABS)[number];

/** An unknown or missing `?tab=` opens Buddies, the first tab. */
export function connectionsTab(requested: string | null | undefined): ConnectionsTab {
  return CONNECTIONS_TABS.includes(requested as ConnectionsTab) ? (requested as ConnectionsTab) : "buddies";
}

export type CountsPart = {
  /** The Connections tab this part opens (only on Εγώ, where the lists are yours). */
  tab: ConnectionsTab;
  /** A key of the `Social` namespace, called with `{ count }`. */
  key: string;
  count: number;
};

/**
 * The line under the name, Buddies first, in three groups that never
 * overlap: «35 Φιλαράκια · 85 σε ακολουθούν · 45 ακολουθείς». On someone
 * else's profile the last two read as their followers and who they follow.
 */
export function countsParts(groups: FollowGroups | null | undefined, mine: boolean): CountsPart[] {
  return [
    { tab: "buddies", key: "countBuddies", count: groups?.buddies ?? 0 },
    { tab: "followers", key: mine ? "countFollowYou" : "countFollowers", count: groups?.followers_only ?? 0 },
    { tab: "following", key: mine ? "countYouFollow" : "countFollowing", count: groups?.following_only ?? 0 },
  ];
}

/** People search answers from two characters on; shorter input keeps the tabs. */
export function isPeopleSearch(term: string) {
  return term.trim().length >= PEOPLE_SEARCH_MIN;
}

/**
 * The quiet word under a search result's name, as a `Social` key, or `null`
 * when there is nothing worth saying (someone public you have no tie with).
 */
export function relationKey(person: { relation: PeopleRelation; buddy: boolean; my_status: FollowStatus }): string | null {
  if (person.buddy || person.relation === "buddy") return "buddyBadge";
  switch (person.relation) {
    case "club":
      return "relationClub";
    case "follow":
      return person.my_status === "none" ? "followsYou" : "relationYouFollow";
    case "nearby":
      return "relationNearby";
    default:
      return null;
  }
}

/**
 * What the posts tab says to someone who doesn't follow yet, as a `Social`
 * key, or `null` when nothing is held back. Public posts show either way
 * (the API filters by audience); a private person's followers-only posts wait
 * for an accepted request, a public person's come at once with the follow.
 */
export function postsLockKey(profile: Pick<PersonProfile, "is_me" | "my_status" | "private">): string | null {
  if (profile.is_me || profile.my_status === "active") return null;
  if (profile.my_status === "requested") return "lockedRequested";
  return profile.private ? "lockedPrivate" : "lockedFollow";
}

export const PERSON_TABS = ["posts", "media", "prs", "clubs"] as const;
export type PersonTab = (typeof PERSON_TABS)[number];

/** An unknown or missing `?tab=` opens the posts, the first tab. */
export function personTab(requested: string | null | undefined): PersonTab {
  return PERSON_TABS.includes(requested as PersonTab) ? (requested as PersonTab) : "posts";
}

export type MediaTile = {
  /** The square's picture: the first photo's (or the video's poster) smallest rendition. */
  src: string | null;
  /** The blurred 16 px preview shown while the picture loads. */
  placeholder: string | null;
  alt: string;
  /** `album` is several photos; a video shows its length. */
  kind: "photo" | "album" | "video";
  count: number;
  duration: string | null;
  /** Only its author sees a post whose media still process (ADR-157). */
  processing: boolean;
};

/**
 * ADR-231: one square of the profile's «Πολυμέσα» grid, Instagram-like: the
 * post's first photo or the video's poster, with a corner mark for a video
 * (and its length) or for several photos.
 */
export function mediaTile(post: Pick<CommunityPost, "media" | "media_status">): MediaTile | null {
  const media = post.media ?? [];
  const first = media[0];
  if (!first) return null;
  const ready = first.status === "ready";
  const video = first.kind === "video";
  return {
    src: ready ? (first.thumb_url ?? first.feed_url ?? null) : null,
    placeholder: first.placeholder ?? null,
    alt: first.alt_text ?? "",
    kind: video ? "video" : media.length > 1 ? "album" : "photo",
    count: media.length,
    duration: video && first.duration_ms ? formatDuration(first.duration_ms) : null,
    processing: post.media_status !== "ready" || !ready,
  };
}

// Follow notifications (ADR-142, ADR-193 §2).
export const SOCIAL_NOTIFICATION_TYPES = ["new_follower", "follow_requested", "follow_accepted"] as const;
type SocialNotificationType = (typeof SOCIAL_NOTIFICATION_TYPES)[number];

function isSocialNotification(type: string): type is SocialNotificationType {
  return (SOCIAL_NOTIFICATION_TYPES as readonly string[]).includes(type);
}

const text = (payload: Record<string, unknown>, key: string) => (typeof payload[key] === "string" ? (payload[key] as string) : "");

/** `new_follower` opens the follower's profile, as the API's own URL does. */
export function socialNotificationUrl(type: string, payload: Record<string, unknown>): string | null {
  if (type !== "new_follower") return null;
  const follower = text(payload, "follower_id");
  return follower ? `/people/${encodeURIComponent(follower)}` : null;
}

const NOTIFICATION_KEYS: Record<SocialNotificationType, { title: string; body: string; name: string }> = {
  new_follower: { title: "notifNewFollowerTitle", body: "notifNewFollowerBody", name: "follower_nickname" },
  follow_requested: { title: "notifFollowRequestedTitle", body: "notifFollowRequestedBody", name: "follower_nickname" },
  follow_accepted: { title: "notifFollowAcceptedTitle", body: "notifFollowAcceptedBody", name: "person_nickname" },
};

/** The bell's title or body for a follow notice (`Social` keys), or `null` for other types. */
export function socialNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: (key: string, values?: Record<string, string>) => string,
): string | null {
  if (!isSocialNotification(type)) return null;
  const keys = NOTIFICATION_KEYS[type];
  return part === "title" ? t(keys.title) : t(keys.body, { name: text(payload, keys.name) || "—" });
}
