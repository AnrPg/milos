import { describe, expect, it } from "vitest";

import { boxChatHref, parseChatTopic } from "./box-chat-links";

describe("box chat links (ADR-282)", () => {
  it("keeps a known topic and drops anything else", () => {
    expect(parseChatTopic("payment")).toBe("payment");
    expect(parseChatTopic("training")).toBe("training");
    expect(parseChatTopic("spam")).toBeNull();
    expect(parseChatTopic(null)).toBeNull();
  });

  it("links to the box chat with the topic preset", () => {
    expect(boxChatHref("milos-method")).toBe("/b/milos-method/chat");
    expect(boxChatHref("milos-method", "payment")).toBe("/b/milos-method/chat?topic=payment");
    expect(boxChatHref("a b")).toBe("/b/a%20b/chat");
  });
});
