import { describe, expect, it } from "vitest";

import { boxInboxNotificationText } from "./box-inbox-notices";

const i18n = (key: string, values?: Record<string, string>) => `${key}${values ? JSON.stringify(values) : ""}`;

describe("boxInboxNotificationText (ADR-282)", () => {
  it("names who wrote to which box", () => {
    expect(boxInboxNotificationText("box_inbox_message", { nickname: "Γιώργος", box_name: "Milos" }, "title", i18n)).toBe(
      'ntfBoxInboxTitle{"name":"Γιώργος","box":"Milos"}',
    );
  });

  it("names who brought a coach in", () => {
    expect(boxInboxNotificationText("box_inbox_message", { brought_in_by: "Άννα" }, "title", i18n)).toBe('ntfBoxInboxBroughtIn{"by":"Άννα"}');
  });

  it("shows the topic and the message, or a fallback", () => {
    expect(boxInboxNotificationText("box_inbox_message", { topic: "payment", body: "Γεια" }, "body", i18n)).toBe("msgTopicPayment · Γεια");
    expect(boxInboxNotificationText("box_inbox_message", { nickname: "Γ" }, "body", i18n)).toBe('ntfBoxInboxBody{"name":"Γ"}');
  });

  it("leaves other types alone", () => {
    expect(boxInboxNotificationText("chat_message", {}, "title", i18n)).toBeNull();
  });
});
