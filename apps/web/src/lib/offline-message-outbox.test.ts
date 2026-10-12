import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  applyMessageDeliveryFailure,
  mergeMessagesWithPending,
  operationToDisplayMessage,
  prepareMessageRetry,
  reconcileQueuedMessages,
  type QueuedMessageOperation,
} from "@/lib/offline-message-outbox";
import type { ChatMessage } from "@/api/messaging";

function queued(overrides: Partial<QueuedMessageOperation> = {}): QueuedMessageOperation {
  return {
    operationId: "op-1",
    ownerUserId: "user-1",
    threadId: "thread-1",
    body: "Offline message",
    messageType: "chat",
    createdAt: 1,
    status: "pending",
    attempts: 0,
    ...overrides,
  };
}

function message(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: "message-1",
    thread_id: "thread-1",
    sender_id: "user-1",
    body: "Delivered message",
    message_type: "chat",
    inserted_at: "2026-07-19T12:00:00Z",
    client_operation_id: "op-1",
    ...overrides,
  };
}

describe("offline message outbox", () => {
  it("replaces an acknowledged pending message with its canonical server message", () => {
    const merged = mergeMessagesWithPending(
      [message()],
      [queued(), queued({ operationId: "op-2", body: "Still pending", createdAt: 2 })],
    );

    expect(merged).toHaveLength(2);
    expect(merged[0]).toMatchObject({ id: "message-1", delivery_status: "sent" });
    expect(merged[1]).toMatchObject({
      id: "pending:op-2",
      body: "Still pending",
      delivery_status: "pending",
    });
  });

  it("reconciles only the active user's operations in creation order", async () => {
    const operations = [
      queued({ operationId: "op-2", createdAt: 2 }),
      queued({ operationId: "other-user", ownerUserId: "user-2", createdAt: 0 }),
      queued({ operationId: "op-1", createdAt: 1 }),
    ];
    const delivered: string[] = [];
    const removed: string[] = [];

    const deliver = vi.fn(async (operation: QueuedMessageOperation) => {
      delivered.push(operation.operationId);
      return message({
        id: `message-${operation.operationId}`,
        client_operation_id: operation.operationId,
      });
    });

    await reconcileQueuedMessages({
      ownerUserId: "user-1",
      operations,
      deliver,
      remove: async (operationId) => {
        removed.push(operationId);
      },
    });

    expect(delivered).toEqual(["op-1", "op-2"]);
    expect(removed).toEqual(["op-1", "op-2"]);
  });

  it("keeps a failed operation for a later retry", async () => {
    const remove = vi.fn();

    await expect(
      reconcileQueuedMessages({
        ownerUserId: "user-1",
        operations: [queued()],
        deliver: async () => {
          throw new TypeError("network unavailable");
        },
        remove,
      }),
    ).rejects.toThrow("network unavailable");

    expect(remove).not.toHaveBeenCalled();
  });

  it("keeps transient failures pending and parks permanent ones as failed", () => {
    expect(applyMessageDeliveryFailure(queued(), new TypeError("offline"))).toMatchObject({
      status: "pending",
      attempts: 1,
      failure: { category: "transient" },
    });
    expect(applyMessageDeliveryFailure(queued(), new ApiError(503, "down", {}))).toMatchObject({
      status: "pending",
    });
    expect(applyMessageDeliveryFailure(queued(), new ApiError(401, "expired", {}))).toMatchObject({
      status: "pending",
    });
    expect(
      applyMessageDeliveryFailure(queued(), new ApiError(403, "forbidden", { code: "forbidden" })),
    ).toMatchObject({
      status: "failed",
      failure: { category: "permanent", status: 403, code: "forbidden" },
    });
  });

  it("retries a failed message with the same operation id", () => {
    const failed = queued({
      status: "failed",
      attempts: 3,
      lastError: "legacy",
      failure: { category: "permanent", status: 422 },
    });

    expect(prepareMessageRetry(failed)).toMatchObject({
      operationId: "op-1",
      status: "pending",
      attempts: 3,
      failure: undefined,
      lastError: undefined,
    });
  });

  it("exposes the failure reason on the pending bubble", () => {
    const display = operationToDisplayMessage(
      queued({ status: "failed", failure: { category: "permanent", status: 403 } }),
    );

    expect(display).toMatchObject({
      delivery_status: "failed",
      client_operation_id: "op-1",
      delivery_failure: { category: "permanent", status: 403 },
    });
  });
});
