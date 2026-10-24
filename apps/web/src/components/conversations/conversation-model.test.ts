import { describe, expect, it } from "vitest";

import type { PersonConversation, PersonMessage } from "@/api/conversations";

import { badgeText, listedConversations, personLabel, previewLine, settledPending, shownMessages, type PendingMessage } from "./conversation-model";

const message = (id: string, extra: Partial<PersonMessage> = {}): PersonMessage => ({
  id,
  conversation_id: "c1",
  author_id: "u1",
  body: `body ${id}`,
  mine: false,
  client_operation_id: null,
  created_at: "2026-10-24T10:00:00Z",
  ...extra,
});

const pending = (op: string, status: PendingMessage["status"] = "sending"): PendingMessage => ({
  client_operation_id: op,
  body: `draft ${op}`,
  created_at: "2026-10-24T10:05:00Z",
  status,
});

const conversation = (id: string, last: PersonMessage | null): PersonConversation => ({
  id,
  person: { id: `p-${id}`, nickname: null, handle: null, avatar_url: null },
  folder: "inbox",
  buddy: false,
  started_by_me: false,
  unread: false,
  last_message_at: last?.created_at ?? null,
  last_message: last,
});

describe("shownMessages", () => {
  it("shows the oldest first and the newest last, across pages, each once", () => {
    const pages = [
      { messages: [message("m4"), message("m3")], next_cursor: "x" },
      { messages: [message("m3"), message("m2"), message("m1")], next_cursor: null },
    ];
    expect(shownMessages(pages).map((item) => item.key)).toEqual(["m1", "m2", "m3", "m4"]);
  });

  it("puts pending sends after the sent ones, and never shows one twice", () => {
    const pages = [{ messages: [message("m2", { mine: true, client_operation_id: "op1" }), message("m1")] }];
    const shown = shownMessages(pages, [pending("op1"), pending("op2", "failed")]);
    expect(shown.map((item) => [item.kind, item.key])).toEqual([
      ["sent", "m1"],
      ["sent", "m2"],
      ["pending", "op2"],
    ]);
  });

  it("is empty with no pages", () => {
    expect(shownMessages([])).toEqual([]);
  });
});

describe("settledPending", () => {
  it("drops the sends the API now holds and keeps the rest", () => {
    const pages = [{ messages: [message("m1", { client_operation_id: "op1" })] }];
    expect(settledPending([pending("op1"), pending("op2")], pages).map((item) => item.client_operation_id)).toEqual(["op2"]);
  });
});

describe("listedConversations", () => {
  it("lists each conversation once and leaves out the ones without a message", () => {
    const pages = [
      { conversations: [conversation("a", message("m1")), conversation("b", null)], next_cursor: "x" },
      { conversations: [conversation("a", message("m1")), conversation("c", message("m2"))], next_cursor: null },
    ];
    expect(listedConversations(pages).map((item) => item.id)).toEqual(["a", "c"]);
  });
});

describe("text helpers", () => {
  it("caps the badge at 99+", () => {
    expect(badgeText(7)).toBe("7");
    expect(badgeText(120)).toBe("99+");
  });

  it("keeps a preview on one line and short", () => {
    expect(previewLine("  hello\n\nthere  ")).toBe("hello there");
    expect(previewLine("a".repeat(100), 10)).toBe(`${"a".repeat(9)}…`);
  });

  it("names a person by nickname, then @handle, then the fallback", () => {
    expect(personLabel({ nickname: "Eleni", handle: "eleni" }, "Someone")).toBe("Eleni");
    expect(personLabel({ nickname: null, handle: "eleni" }, "Someone")).toBe("@eleni");
    expect(personLabel({}, "Someone")).toBe("Someone");
  });
});
