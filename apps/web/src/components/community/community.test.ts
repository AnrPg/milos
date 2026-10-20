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

describe("club page helpers", async () => {
  const { builtInChannel, channelSections, gymClubFor } = await import("./community");

  it("picks the selected gym's club, else the first gym club", () => {
    const clubs = [club("a", []), club("b", [])];
    expect(gymClubFor(clubs, "org-b")?.id).toBe("b");
    expect(gymClubFor(clubs, "org-x")?.id).toBe("a");
    expect(gymClubFor([], "org-a")).toBeNull();
  });

  it("finds a built-in channel by kind", () => {
    const gym = club("a", [channel("a1", "announcements", false), channel("a2", "wod", true)]);
    expect(builtInChannel(gym, "wod")?.id).toBe("a2");
    expect(builtInChannel(gym, "challenges")).toBeNull();
    expect(builtInChannel(null, "wod")).toBeNull();
  });

  it("groups channels with offered class groups first", () => {
    const group = (id: string, name: string, suggested: boolean) => ({ ...channel(id, "class_slot", false), name, suggested });
    const sections = channelSections([
      channel("w", "wod", true),
      group("g1", "CrossFit 07:00", false),
      group("g2", "CrossFit 18:00", true),
      channel("s", "season", false),
    ]);
    expect(sections.box.map((c) => c.id)).toEqual(["w"]);
    expect(sections.classes.map((c) => c.id)).toEqual(["g2", "g1"]);
    expect(sections.other.map((c) => c.id)).toEqual(["s"]);
  });
});

describe("open clubs and member groups (ADR-143)", async () => {
  const { channelSections, initialComposeTarget } = await import("./community");

  it("lists #γενικά with the club's own channels and leaves member groups to their card", () => {
    const sections = channelSections([
      channel("a", "announcements", false),
      channel("g", "general", true),
      { ...channel("m", "member_group", true), name: "Τρέξιμο" },
      channel("s", "season", false),
    ]);
    expect(sections.box.map((c) => c.id)).toEqual(["a", "g"]);
    expect(sections.other.map((c) => c.id)).toEqual(["s"]);
  });

  it("names #γενικά by its kind", () => {
    expect(channelNameKey({ kind: "general", name: null })).toBe("channel.general");
  });

  it("opens compose on the channel being read when the member may post there", () => {
    const clubs = [club("a", [channel("w", "wod", true), { ...channel("m", "member_group", true), name: "Τρέξιμο" }])];
    expect(initialComposeTarget(clubs, null, "a", "m")).toEqual({ kind: "channel", channelId: "m", public: false });
    expect(initialComposeTarget(clubs, null, "a", "nope")).toEqual({ kind: "channel", channelId: "w", public: false });
  });
});
