import { describe, expect, it } from "vitest";

import { buildOutboxSnapshot, commandEntry, messageEntry } from "@/lib/outbox-snapshot";

describe("outbox snapshot", () => {
  it("groups message and command operations into pending and failed, oldest first", () => {
    const message = messageEntry({
      operationId: "m-1",
      ownerUserId: "u",
      threadId: "t",
      body: "x".repeat(120),
      messageType: "chat",
      createdAt: 3,
      status: "failed",
      attempts: 1,
      failure: { category: "permanent", status: 403 },
    });
    const command = commandEntry(
      {
        operationId: "c-1",
        kind: "booking.request",
        ownerUserId: "u",
        organizationSlug: null,
        payload: { slotId: "s", label: "Morning WOD" },
        createdAt: 1,
        status: "pending",
        attempts: 0,
      },
      () => ({ labelKey: "outboxKindBookingRequest", detail: "Morning WOD" }),
    );
    const unknown = commandEntry(
      {
        operationId: "c-2",
        kind: "legacy.kind",
        ownerUserId: "u",
        organizationSlug: null,
        payload: {},
        createdAt: 2,
        status: "failed",
        attempts: 0,
        failure: { category: "permanent", code: "unsupported_operation" },
      },
      () => null,
    );

    const snapshot = buildOutboxSnapshot([message, command, unknown]);

    expect(snapshot.pending.map((entry) => entry.operationId)).toEqual(["c-1"]);
    expect(snapshot.failed.map((entry) => entry.operationId)).toEqual(["c-2", "m-1"]);
    expect(message.detail).toHaveLength(80);
    expect(unknown.labelKey).toBe("outboxKindUnknown");
  });
});
