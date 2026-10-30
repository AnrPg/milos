import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import { BUDDIES_KEY } from "@/api/buddies";
import { PARTNERS_OVERVIEW_KEY, PARTNER_MATCHES_KEY, partnerDeckKey, partnerMessagesKey } from "@/api/partners";

import { applyPartnersEvent, parsePartnersEvent } from "./partners-realtime";

function seeded() {
  const client = new QueryClient();
  const keys = {
    matches: [...PARTNER_MATCHES_KEY],
    chat1: [...partnerMessagesKey("m1")],
    chat2: [...partnerMessagesKey("m2")],
    overview: [...PARTNERS_OVERVIEW_KEY],
    deck: [...partnerDeckKey({ time: "early" })],
    buddy: [...BUDDIES_KEY],
  };
  Object.values(keys).forEach((key) => client.setQueryData(key, { seeded: true }));
  const stale = () =>
    Object.entries(keys)
      .filter(([, key]) => client.getQueryState(key)?.isInvalidated)
      .map(([name]) => name)
      .sort();
  return { client, stale };
}

describe("partners realtime", () => {
  it("parses known kinds only", () => {
    expect(parsePartnersEvent({ kind: "partner_message_created", match_id: "m1" })).toEqual({ kind: "partner_message_created", match_id: "m1" });
    expect(parsePartnersEvent({ kind: "buddy_message_created" })).toBeNull();
    expect(parsePartnersEvent("nope")).toBeNull();
  });

  it("a message refreshes the list and that conversation only", () => {
    const { client, stale } = seeded();
    expect(applyPartnersEvent(client, { kind: "partner_message_created", match_id: "m1" })).toBe(true);
    expect(stale()).toEqual(["chat1", "matches"]);
  });

  it("a match change refreshes everything Partners but nothing else", () => {
    const { client, stale } = seeded();
    applyPartnersEvent(client, { kind: "partner_match_changed", match_id: "m2" });
    expect(stale()).toEqual(["chat1", "chat2", "deck", "matches", "overview"]);
  });

  it("ignores unknown payloads", () => {
    const { client, stale } = seeded();
    expect(applyPartnersEvent(client, { kind: "other" })).toBe(false);
    expect(stale()).toEqual([]);
  });
});
