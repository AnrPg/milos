import { describe, expect, it } from "vitest";

import type { BuddyLink, SupportRequest } from "@/api/buddies";

import {
  activeBuddies,
  breathingState,
  canStillUndo,
  clock,
  freeBuddySlots,
  insideQuietHours,
  latestOpenRequest,
  nudgeDue,
  quietHoursLabel,
  receivedToShow,
  recipientNames,
  replyText,
  senderPhase,
  shiftWeek,
  telHref,
  undoSecondsLeft,
  unreadTotal,
  validQuietHours,
  weekStart,
} from "./buddy-model";

const now = Date.parse("2026-10-21T20:00:00Z");
const at = (seconds: number) => new Date(now + seconds * 1000).toISOString();

const link = (overrides: Partial<BuddyLink> = {}): BuddyLink => ({
  id: "link-1",
  role: "requester",
  status: "active",
  person: { id: "u-1", nickname: "Dimitra", avatar_url: null },
  via_link: false,
  receives_weekly_summary: false,
  ended_by_me: false,
  ...overrides,
});

const request = (overrides: Partial<SupportRequest> = {}): SupportRequest => ({
  id: "req-1",
  role: "sender",
  message: null,
  created_at: at(-1),
  status: "sending",
  can_undo: true,
  undo_until: at(4),
  replies: [],
  nudge: { due: false, due_at: at(600), breathing_seconds: 120, can_resend: true, suggestions: ["breathing", "water", "walk"] },
  ...overrides,
});

describe("undo window", () => {
  it("counts whole seconds down and stops at zero", () => {
    expect(undoSecondsLeft(at(4.2), now)).toBe(5);
    expect(undoSecondsLeft(at(0.1), now)).toBe(1);
    expect(undoSecondsLeft(at(-1), now)).toBe(0);
    expect(undoSecondsLeft(null, now)).toBe(0);
    expect(undoSecondsLeft("nonsense", now)).toBe(0);
  });

  it("never shows more than five seconds, even with a slow clock", () => {
    expect(undoSecondsLeft(at(30), now)).toBe(5);
  });

  it("hides undo once taken back or refused by the server", () => {
    expect(canStillUndo(request(), now)).toBe(true);
    expect(canStillUndo(request({ status: "undone" }), now)).toBe(false);
    expect(canStillUndo(request({ can_undo: false }), now)).toBe(false);
    expect(canStillUndo(request({ undo_until: at(-0.5) }), now)).toBe(false);
  });
});

describe("quiet hours", () => {
  it("labels the range", () => {
    expect(quietHoursLabel({ from: "23:00", to: "07:00" })).toBe("23:00–07:00");
    expect(quietHoursLabel(null)).toBeNull();
  });

  it("wraps overnight ranges past midnight", () => {
    const night = { from: "23:00", to: "07:00" };
    expect(insideQuietHours(night, "23:30")).toBe(true);
    expect(insideQuietHours(night, "03:00")).toBe(true);
    expect(insideQuietHours(night, "07:00")).toBe(false);
    expect(insideQuietHours(night, "12:00")).toBe(false);
    expect(insideQuietHours({ from: "13:00", to: "15:00" }, "14:00")).toBe(true);
    expect(insideQuietHours(null, "14:00")).toBe(false);
  });

  it("accepts only two different HH:MM times", () => {
    expect(validQuietHours("23:00", "07:00")).toBe(true);
    expect(validQuietHours("23:00", "23:00")).toBe(false);
    expect(validQuietHours("25:00", "07:00")).toBe(false);
  });
});

describe("reply text", () => {
  const t = (key: string) => ({ "reply.here": "I'm here", "reply.walk": "Shall we go for a walk?", "reply.call": "Call me" })[key] ?? key;

  it("uses the quick reply's words, then the buddy's own", () => {
    expect(replyText({ kind: "here" }, t)).toBe("I'm here");
    expect(replyText({ kind: "walk", text: "At 10?" }, t)).toBe("Shall we go for a walk? At 10?");
    expect(replyText({ kind: "text", text: "  On my way  " }, t)).toBe("On my way");
  });
});

describe("breathing timer", () => {
  it("breathes in for four seconds, holds for two, out for four", () => {
    expect(breathingState(0)).toMatchObject({ phase: "in", phaseLeft: 4, remaining: 120, scale: 0, done: false });
    expect(breathingState(2).scale).toBeCloseTo(0.5);
    expect(breathingState(4.5)).toMatchObject({ phase: "hold", scale: 1 });
    expect(breathingState(8)).toMatchObject({ phase: "out", phaseLeft: 2 });
    expect(breathingState(10)).toMatchObject({ phase: "in" });
  });

  it("finishes after two minutes", () => {
    expect(breathingState(119.5).done).toBe(false);
    expect(breathingState(120)).toMatchObject({ done: true, remaining: 0 });
    expect(breathingState(500).done).toBe(true);
  });

  it("formats the clock", () => {
    expect(clock(120)).toBe("2:00");
    expect(clock(65)).toBe("1:05");
    expect(clock(-3)).toBe("0:00");
  });
});

describe("who it goes to", () => {
  const overview = {
    buddies: [link(), link({ id: "link-2", status: "pending", person: { id: "u-2", nickname: "Kostas" } }), link({ id: "link-3", person: { id: "u-3", nickname: "Nikos" }, unread_messages: 2 })],
    supporting: [link({ id: "link-4", role: "buddy", unread_messages: 1 })],
    invitations: [],
    max_buddies: 2,
    invite_days: 7,
  };

  it("names only active buddies", () => {
    expect(recipientNames(activeBuddies(overview), "someone")).toBe("Dimitra, Nikos");
  });

  it("counts open slots and unread messages", () => {
    expect(freeBuddySlots(overview)).toBe(0);
    expect(freeBuddySlots({ buddies: [link()], max_buddies: 2 })).toBe(1);
    expect(unreadTotal(overview)).toBe(3);
    expect(unreadTotal({})).toBe(0);
  });
});

describe("sender status", () => {
  it("moves from sending to waiting to the calm card", () => {
    expect(senderPhase(request(), now)).toBe("sending");
    expect(senderPhase(request({ status: "delivered", can_undo: false }), now)).toBe("waiting");
    expect(senderPhase(request({ status: "delivered", can_undo: false }), now + 601_000)).toBe("noReply");
    expect(senderPhase(request({ status: "delivered", nudge: { due: true } }), now)).toBe("noReply");
  });

  it("a reply or an undo ends the wait", () => {
    const reply = { id: "r-1", kind: "here" as const, person: null, created_at: at(0) };
    expect(senderPhase(request({ status: "delivered", replies: [reply] }), now + 601_000)).toBe("replied");
    expect(nudgeDue(request({ status: "delivered", replies: [reply], nudge: { due: true } }), now)).toBe(false);
    expect(senderPhase(request({ status: "undone" }), now)).toBe("undone");
  });

  it("keeps the latest open request of the last two hours", () => {
    const old = request({ id: "old", created_at: new Date(now - 3 * 3600_000).toISOString() });
    const undone = request({ id: "undone", status: "undone", created_at: at(-10) });
    const recent = request({ id: "recent", created_at: at(-60) });
    expect(latestOpenRequest([old, undone, recent], now)?.id).toBe("recent");
    expect(latestOpenRequest([old], now)).toBeNull();
  });

  it("shows a buddy only delivered requests of the last day", () => {
    const delivered = request({ id: "d", role: "buddy", status: "delivered" });
    const sending = request({ id: "s", role: "buddy", status: "sending" });
    expect(receivedToShow([delivered, sending], now).map((item) => item.id)).toEqual(["d"]);
  });
});

describe("small helpers", () => {
  it("builds a tel link", () => {
    expect(telHref("+30 690 000 0000")).toBe("tel:+306900000000");
    expect(telHref("690-000")).toBe("tel:690000");
  });

  it("finds and shifts the week", () => {
    expect(weekStart("2026-10-21")).toBe("2026-10-19");
    expect(weekStart("2026-10-25")).toBe("2026-10-19");
    expect(shiftWeek("2026-10-19", -1)).toBe("2026-10-12");
  });
});
