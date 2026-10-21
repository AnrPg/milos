import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import { BUDDIES_KEY, SUPPORT_REQUESTS_KEY } from "@/api/buddies";

import { applyBuddyEvent, buddyCacheRefreshes, buddyTopic, parseBuddyEvent } from "./buddy-realtime";

function seeded() {
  const client = new QueryClient();
  const keys = {
    overview: [...BUDDIES_KEY],
    candidates: [...BUDDIES_KEY, "candidates", ""],
    chat1: [...BUDDIES_KEY, "l1", "messages"],
    chat2: [...BUDDIES_KEY, "l2", "messages"],
    sent: [...SUPPORT_REQUESTS_KEY, "sent"],
    received: [...SUPPORT_REQUESTS_KEY, "received"],
    r1: [...SUPPORT_REQUESTS_KEY, "one", "r1"],
    r2: [...SUPPORT_REQUESTS_KEY, "one", "r2"],
    other: ["my", "wellness"],
  };
  Object.values(keys).forEach((key) => client.setQueryData(key, { seeded: true }));
  const stale = () =>
    Object.entries(keys)
      .filter(([, key]) => client.getQueryState(key)?.isInvalidated)
      .map(([name]) => name)
      .sort();
  return { client, stale };
}

describe("buddy realtime events", () => {
  it("reads only known events, with ids", () => {
    expect(parseBuddyEvent({ kind: "buddy_message_created", link_id: "l1", body: "x" })).toEqual({
      kind: "buddy_message_created",
      link_id: "l1",
      request_id: undefined,
    });
    expect(parseBuddyEvent({ kind: "something_else" })).toBeNull();
    expect(parseBuddyEvent(null)).toBeNull();
    expect(parseBuddyEvent("buddy_link_changed")).toBeNull();
    expect(buddyTopic("u1")).toBe("user:u1");
  });

  it("a delivered request refreshes the lists and that request only", () => {
    const { client, stale } = seeded();
    expect(applyBuddyEvent(client, { kind: "support_request_delivered", request_id: "r1" })).toBe(true);
    expect(stale()).toEqual(["r1", "received", "sent"]);
  });

  it("a sent, undone or nudged request is the sender's own", () => {
    const { client, stale } = seeded();
    applyBuddyEvent(client, { kind: "support_request_undone", request_id: "r2" });
    expect(stale()).toEqual(["r2", "sent"]);
  });

  it("a reply refreshes the request, the conversation and the unread counts", () => {
    const { client, stale } = seeded();
    applyBuddyEvent(client, { kind: "support_reply_created", request_id: "r1", link_id: "l1" });
    expect(stale()).toEqual(["chat1", "overview", "r1", "received", "sent"]);
  });

  it("a message or a read receipt refreshes that conversation and the badges", () => {
    const { client, stale } = seeded();
    applyBuddyEvent(client, { kind: "buddy_messages_read", link_id: "l2" });
    expect(stale()).toEqual(["chat2", "overview"]);
  });

  it("a link change refreshes everything under Buddy but not the requests", () => {
    const { client, stale } = seeded();
    applyBuddyEvent(client, { kind: "buddy_link_changed", link_id: "l1" });
    expect(stale()).toEqual(["candidates", "chat1", "chat2", "overview"]);
  });

  it("an unknown payload changes nothing", () => {
    const { client, stale } = seeded();
    expect(applyBuddyEvent(client, { kind: "chat_message" })).toBe(false);
    expect(stale()).toEqual([]);
  });

  it("an event without ids still refreshes the lists", () => {
    expect(buddyCacheRefreshes({ kind: "buddy_message_created" })).toEqual([{ queryKey: BUDDIES_KEY, exact: true }]);
  });
});
