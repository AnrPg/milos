import { describe, expect, it } from "vitest";

import type { CommunityClub, CommunityPost } from "@/api/community";

import { channelNameKey, clubInitials, defaultChannelId, postableChannels, withoutPinned } from "./community";

const channel = (id: string, kind: CommunityClub["channels"][number]["kind"], canPost: boolean) => ({
  id,
  kind,
  name: null,
  write_policy: "members" as const,
  membership: "everyone" as const,
  joined: true,
  can_post: canPost,
  can_leave: false,
});

const club = (id: string, channels: CommunityClub["channels"]): CommunityClub => ({
  id,
  organization_id: `org-${id}`,
  organization_slug: id,
  kind: "gym",
  name: `Club ${id}`,
  role: "member",
  notify_level: "all",
  channels,
});

describe("community helpers", () => {
  it("names built-in channels by kind and custom ones by their name", () => {
    expect(channelNameKey({ kind: "wod", name: null })).toBe("channel.wod");
    expect(channelNameKey({ kind: "custom", name: "τρέξιμο" })).toBeNull();
    expect(channelNameKey({ kind: "class_slot", name: null })).toBe("channel.class_slot");
  });

  it("makes club initials", () => {
    expect(clubInitials("Box Κυψέλη")).toBe("BΚ");
    expect(clubInitials("hyrox")).toBe("HY");
  });

  it("lists only channels the member may post in and defaults to #wod", () => {
    const clubs = [club("a", [channel("a1", "announcements", false), channel("a2", "wod", true)])];
    expect(postableChannels(clubs).map((option) => option.channel.id)).toEqual(["a2"]);
    expect(defaultChannelId(clubs)).toBe("a2");
    expect(defaultChannelId(clubs, "missing")).toBeNull();
  });

  it("shows a pinned post once", () => {
    const post = (id: string) => ({ id }) as CommunityPost;
    expect(withoutPinned([post("1"), post("2")], [post("2")]).map((p) => p.id)).toEqual(["1"]);
  });
});

describe("attachments", async () => {
  const { attachmentTypeOf } = await import("./community");
  it("maps shareable journal kinds", () => {
    expect(attachmentTypeOf("execution")).toBe("workout_execution");
    expect(attachmentTypeOf("training_log")).toBe("training_log_entry");
    expect(attachmentTypeOf("pr")).toBe("pr");
    expect(attachmentTypeOf("note")).toBeNull();
  });
});
