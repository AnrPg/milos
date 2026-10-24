import { describe, expect, it } from "vitest";

import type { ChatThread } from "@/api/messaging";

import { inboxHref, parseInboxSegment, showsIn, threadSegment, threadsIn, type ThreadSegmentContext } from "./inbox-model";

function thread(id: string, context_type: ChatThread["context_type"], others: string[] = [], context_id: string | null = null): ChatThread {
  return {
    id,
    context_type,
    context_id,
    created_by_id: "me",
    inserted_at: "2026-10-24T08:00:00Z",
    participants: ["me", ...others].map((user_id) => ({ id: `${id}-${user_id}`, user_id, nickname: user_id, last_read_message_id: null })),
  };
}

const context: ThreadSegmentContext = {
  currentUserId: "me",
  coachPeerIds: new Set(["coach-nikos"]),
  coachingThreadIds: new Set(["t-coaching"]),
};

describe("inbox model", () => {
  it("reads the segment from ?filter= and falls back to «Όλα»", () => {
    expect(parseInboxSegment("coach")).toBe("coach");
    expect(parseInboxSegment("partners")).toBe("partners");
    expect(parseInboxSegment("chats")).toBe("all");
    expect(parseInboxSegment(null)).toBe("all");
  });

  it("builds the inbox address", () => {
    expect(inboxHref()).toBe("/messages");
    expect(inboxHref({ filter: "coach" })).toBe("/messages?filter=coach");
    expect(inboxHref({ filter: "all", thread: "t 1" })).toBe("/messages?thread=t+1");
  });

  it("files gym threads by who they are with", () => {
    expect(threadSegment(thread("a", "assignment"), context)).toBe("coach");
    expect(threadSegment(thread("d1", "direct", ["coach-nikos"]), context)).toBe("coach");
    expect(threadSegment(thread("d2", "direct", ["friend"]), context)).toBeNull();
    expect(threadSegment(thread("t-coaching", "direct", ["someone"]), context)).toBe("coach");
    expect(threadSegment(thread("b", "box", [], "me"), context)).toBe("clubs");
    expect(threadSegment(thread("c", "class_slot"), context)).toBe("clubs");
  });

  it("shows everything under «Όλα» and only matching threads elsewhere", () => {
    const all = [thread("a", "assignment"), thread("d2", "direct", ["friend"]), thread("b", "box")];
    expect(threadsIn(all, "all", context).map((item) => item.id)).toEqual(["a", "d2", "b"]);
    expect(threadsIn(all, "coach", context).map((item) => item.id)).toEqual(["a"]);
    expect(threadsIn(all, "clubs", context).map((item) => item.id)).toEqual(["b"]);
    expect(threadsIn(all, "partners", context)).toEqual([]);
    expect(showsIn(["partners"], "all")).toBe(true);
    expect(showsIn(["partners"], "coach")).toBe(false);
    expect(showsIn([], "all")).toBe(true);
  });
});
