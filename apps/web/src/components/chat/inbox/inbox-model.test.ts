import { describe, expect, it } from "vitest";

import type { ChatThread } from "@/api/messaging";

import {
  awaitsBoxReply,
  boxInboxThreads,
  inboxHref,
  isBoxInboxThread,
  parseInboxSegment,
  showsIn,
  threadSegment,
  threadsIn,
  visibleSegments,
  type ThreadSegmentContext,
} from "./inbox-model";

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
    expect(threadSegment(thread("d2", "direct", ["friend"]), context)).toBe("people");
    expect(threadSegment(thread("t-coaching", "direct", ["someone"]), context)).toBe("coach");
    expect(threadSegment(thread("b", "box", [], "me"), context)).toBe("clubs");
    expect(threadSegment(thread("c", "class_slot"), context)).toBe("clubs");
  });

  it("shows everything under «Όλα» and only matching threads elsewhere", () => {
    const all = [thread("a", "assignment"), thread("d2", "direct", ["friend"]), thread("b", "box")];
    expect(threadsIn(all, "all", context).map((item) => item.id)).toEqual(["a", "d2", "b"]);
    expect(threadsIn(all, "coach", context).map((item) => item.id)).toEqual(["a"]);
    expect(threadsIn(all, "clubs", context).map((item) => item.id)).toEqual(["b"]);
    expect(threadsIn(all, "people", context).map((item) => item.id)).toEqual(["d2"]);
    expect(threadsIn(all, "partners", context)).toEqual([]);
    expect(showsIn(["partners"], "all")).toBe(true);
    expect(showsIn(["partners"], "coach")).toBe(false);
    expect(showsIn([], "all")).toBe(true);
  });

  it("offers «Partners» only to someone who has one", () => {
    expect(visibleSegments({ hasPartners: false })).toEqual(["all", "people", "coach", "clubs"]);
    expect(visibleSegments({ hasPartners: true })).toEqual(["all", "people", "coach", "clubs", "partners"]);
    expect(parseInboxSegment("people")).toBe("people");
  });

  describe("the box's inbox (ADR-282)", () => {
    const boxThread = (id: string, person: string, lastSender: string | null, at: string): ChatThread => ({
      ...thread(id, "box", [person], person),
      last_message: lastSender
        ? { id: `${id}-m`, sender_id: lastSender, body: "…", message_type: "chat", topic: null, inserted_at: at }
        : null,
    });

    const waiting = boxThread("b1", "giorgos", "giorgos", "2026-10-30T10:00:00Z");
    const answered = boxThread("b2", "eleni", "me", "2026-10-30T11:00:00Z");
    const newer = boxThread("b3", "nikos", "nikos", "2026-10-30T12:00:00Z");

    it("is the box's thread with someone else, never the person's own", () => {
      expect(isBoxInboxThread(waiting, "me")).toBe(true);
      expect(isBoxInboxThread(waiting, "giorgos")).toBe(false);
      expect(isBoxInboxThread(thread("d", "direct", ["x"]), "me")).toBe(false);
    });

    it("waits for an answer when the person wrote last", () => {
      expect(awaitsBoxReply(waiting)).toBe(true);
      expect(awaitsBoxReply(answered)).toBe(false);
      expect(awaitsBoxReply(boxThread("b4", "x", null, "2026-10-30T09:00:00Z"))).toBe(false);
    });

    it("«Αναπάντητα» keeps the waiting threads, newest first; «Όλα» keeps every one", () => {
      expect(boxInboxThreads([waiting, answered, newer], "unanswered").map((t) => t.id)).toEqual(["b3", "b1"]);
      expect(boxInboxThreads([waiting, answered, newer], "all").map((t) => t.id)).toEqual(["b3", "b2", "b1"]);
    });
  });
});
