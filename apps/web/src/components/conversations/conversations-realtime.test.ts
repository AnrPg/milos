import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import {
  CONVERSATIONS_UNREAD_KEY,
  conversationKey,
  conversationListKey,
  conversationMessagesKey,
} from "@/api/conversations";

import { applyConversationEvent, parseConversationEvent } from "./conversations-realtime";

function seeded() {
  const client = new QueryClient();
  const keys = {
    inbox: [...conversationListKey("inbox"), null],
    requests: [...conversationListKey("requests"), null],
    unread: [...CONVERSATIONS_UNREAD_KEY],
    c1: [...conversationKey("c1")],
    c1Messages: [...conversationMessagesKey("c1")],
    c2: [...conversationKey("c2")],
    c2Messages: [...conversationMessagesKey("c2")],
    other: ["my", "buddies"],
  };
  Object.values(keys).forEach((key) => client.setQueryData(key, { seeded: true }));
  const stale = () =>
    Object.entries(keys)
      .filter(([, key]) => client.getQueryState(key)?.isInvalidated)
      .map(([name]) => name)
      .sort();
  return { client, stale };
}

describe("conversation realtime events", () => {
  it("reads only known events with a conversation id, and never keeps other fields", () => {
    expect(parseConversationEvent({ kind: "message_created", conversation_id: "c1", message_id: "m1", body: "x" })).toEqual({
      kind: "message_created",
      conversation_id: "c1",
      message_id: "m1",
    });
    expect(parseConversationEvent({ kind: "read" })).toBeNull();
    expect(parseConversationEvent({ kind: "typing", conversation_id: "c1" })).toBeNull();
    expect(parseConversationEvent(null)).toBeNull();
  });

  it("a new message refreshes the lists, the count, that conversation and its messages", () => {
    const { client, stale } = seeded();
    expect(applyConversationEvent(client, { kind: "message_created", conversation_id: "c1", message_id: "m1" })).toBe(true);
    expect(stale()).toEqual(["c1", "c1Messages", "inbox", "requests", "unread"]);
  });

  it("a read or a folder change leaves the messages alone", () => {
    const { client, stale } = seeded();
    applyConversationEvent(client, { kind: "folder_changed", conversation_id: "c2" });
    expect(stale()).toEqual(["c2", "inbox", "requests", "unread"]);
  });

  it("an unknown payload changes nothing", () => {
    const { client, stale } = seeded();
    expect(applyConversationEvent(client, { kind: "nope", conversation_id: "c1" })).toBe(false);
    expect(stale()).toEqual([]);
  });
});
