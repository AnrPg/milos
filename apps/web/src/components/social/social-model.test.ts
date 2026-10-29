import { describe, expect, it } from "vitest";

import { notificationTargetUrl } from "@/components/notifications/notification-links";

import {
  CONNECTIONS_TABS,
  connectionsTab,
  countsParts,
  isPeopleSearch,
  mediaTile,
  personTab,
  postsLockKey,
  relationKey,
  socialNotificationText,
  socialNotificationUrl,
} from "./social-model";

const t = (key: string, values?: Record<string, string>) =>
  values ? `${key}(${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(",")})` : key;

describe("Connections tabs", () => {
  it("has six tabs, Buddies first, so the picker lays them out 2×3", () => {
    expect(CONNECTIONS_TABS).toEqual(["buddies", "followers", "following", "boxes", "clubs", "prs"]);
  });

  it("opens Buddies for a missing or unknown tab", () => {
    expect(connectionsTab(null)).toBe("buddies");
    expect(connectionsTab("nope")).toBe("buddies");
    expect(connectionsTab("following")).toBe("following");
  });
});

describe("counts line", () => {
  const groups = { buddies: 35, followers_only: 85, following_only: 45 };

  it("puts Buddies first and links each part to its tab on Εγώ", () => {
    expect(countsParts(groups, true)).toEqual([
      { tab: "buddies", key: "countBuddies", count: 35 },
      { tab: "followers", key: "countFollowYou", count: 85 },
      { tab: "following", key: "countYouFollow", count: 45 },
    ]);
  });

  it("speaks of their followers on someone else's profile", () => {
    expect(countsParts(groups, false).map((part) => part.key)).toEqual(["countBuddies", "countFollowers", "countFollowing"]);
  });

  it("reads zeros while the counts load", () => {
    expect(countsParts(undefined, true).map((part) => part.count)).toEqual([0, 0, 0]);
  });
});

describe("people search", () => {
  it("starts from two characters", () => {
    expect(isPeopleSearch("m")).toBe(false);
    expect(isPeopleSearch(" m ")).toBe(false);
    expect(isPeopleSearch("ma")).toBe(true);
  });

  it("names the tie quietly, Buddy first", () => {
    expect(relationKey({ relation: "buddy", buddy: true, my_status: "active" })).toBe("buddyBadge");
    expect(relationKey({ relation: "club", buddy: true, my_status: "active" })).toBe("buddyBadge");
    expect(relationKey({ relation: "club", buddy: false, my_status: "none" })).toBe("relationClub");
    expect(relationKey({ relation: "follow", buddy: false, my_status: "none" })).toBe("followsYou");
    expect(relationKey({ relation: "follow", buddy: false, my_status: "requested" })).toBe("relationYouFollow");
    expect(relationKey({ relation: "nearby", buddy: false, my_status: "none" })).toBe("relationNearby");
    expect(relationKey({ relation: "public", buddy: false, my_status: "none" })).toBeNull();
  });
});

describe("posts lock", () => {
  it("says nothing to followers or on your own profile", () => {
    expect(postsLockKey({ is_me: true, my_status: "none", private: true })).toBeNull();
    expect(postsLockKey({ is_me: false, my_status: "active", private: true })).toBeNull();
  });

  it("tells a private account from a public one", () => {
    expect(postsLockKey({ is_me: false, my_status: "none", private: true })).toBe("lockedPrivate");
    expect(postsLockKey({ is_me: false, my_status: "none", private: false })).toBe("lockedFollow");
    expect(postsLockKey({ is_me: false, my_status: "requested", private: true })).toBe("lockedRequested");
  });
});

describe("person tabs", () => {
  it("opens the posts unless a known tab is asked for", () => {
    expect(personTab("media")).toBe("media");
    expect(personTab("reels")).toBe("posts");
    expect(personTab(null)).toBe("posts");
  });
});

describe("media grid tile (ADR-231)", () => {
  const photo = (id: string, extra: Record<string, unknown> = {}) => ({
    id,
    kind: "image" as const,
    status: "ready" as const,
    thumb_url: `https://cdn/${id}/thumb.webp`,
    feed_url: `https://cdn/${id}/feed.webp`,
    placeholder: "data:image/webp;base64,AA",
    alt_text: `Alt ${id}`,
    ...extra,
  });

  it("shows nothing for a post without media", () => {
    expect(mediaTile({ media: [], media_status: "ready" })).toBeNull();
  });

  it("uses the first photo's thumbnail and marks several photos as an album", () => {
    expect(mediaTile({ media: [photo("a")], media_status: "ready" })).toMatchObject({ src: "https://cdn/a/thumb.webp", alt: "Alt a", kind: "photo", count: 1, processing: false });
    expect(mediaTile({ media: [photo("a"), photo("b")], media_status: "ready" })).toMatchObject({ kind: "album", count: 2 });
    expect(mediaTile({ media: [photo("a", { thumb_url: null })], media_status: "ready" })?.src).toBe("https://cdn/a/feed.webp");
  });

  it("shows a video's poster and its length", () => {
    const video = photo("v", { kind: "video", duration_ms: 75_000, video_url: "https://cdn/v.mp4" });
    expect(mediaTile({ media: [video], media_status: "ready" })).toMatchObject({ kind: "video", duration: "1:15", src: "https://cdn/v/thumb.webp" });
  });

  it("marks media that still process (its author's own grid)", () => {
    expect(mediaTile({ media: [photo("a", { status: "processing", thumb_url: null, feed_url: null })], media_status: "processing" })).toMatchObject({ src: null, processing: true });
  });
});

describe("follow notifications", () => {
  it("opens the new follower's profile", () => {
    expect(socialNotificationUrl("new_follower", { follower_id: "u 1" })).toBe("/people/u%201");
    expect(socialNotificationUrl("new_follower", {})).toBeNull();
    expect(socialNotificationUrl("follow_requested", { follower_id: "u1" })).toBeNull();
    expect(notificationTargetUrl({ type: "new_follower", payload: { follower_id: "u1" } }, "member")).toBe("/people/u1");
  });

  it("names who followed, requested or accepted", () => {
    expect(socialNotificationText("new_follower", { follower_nickname: "Maria" }, "title", t)).toBe("notifNewFollowerTitle");
    expect(socialNotificationText("new_follower", { follower_nickname: "Maria" }, "body", t)).toBe("notifNewFollowerBody(name=Maria)");
    expect(socialNotificationText("follow_accepted", { person_nickname: "Nikos" }, "body", t)).toBe("notifFollowAcceptedBody(name=Nikos)");
    expect(socialNotificationText("follow_requested", {}, "body", t)).toBe("notifFollowRequestedBody(name=—)");
    expect(socialNotificationText("chat_message", {}, "title", t)).toBeNull();
  });
});
