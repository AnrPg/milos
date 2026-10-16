import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { approveBooking, createBooking } from "@/api/schedule";
import { createTrainingLogEntry } from "@/api/training-log";
import {
  bookingApproveAdapter,
  bookingRequestAdapter,
  getOutboxCommandAdapter,
  registeredOutboxCommandKinds,
  trainingLogCreateAdapter,
} from "@/lib/offline-command-adapters";
import {
  createMemoryCommandStore,
  prepareCommandRetry,
  reconcileOutboxCommands,
  submitOutboxCommand,
  type OutboxCommandAdapter,
  type QueuedCommandOperation,
} from "@/lib/offline-command-outbox";

vi.mock("@/api/schedule", () => ({
  createBooking: vi.fn(),
  approveBooking: vi.fn(),
  rejectBooking: vi.fn(),
}));

vi.mock("@/api/training-log", () => ({
  createTrainingLogEntry: vi.fn(),
}));

function apiError(status: number, code?: string) {
  return new ApiError(status, code ?? "error", code ? { code } : {});
}

function queued(overrides: Partial<QueuedCommandOperation> = {}): QueuedCommandOperation {
  return {
    operationId: "op-1",
    kind: "booking.request",
    ownerUserId: "user-1",
    organizationSlug: "atlas",
    payload: { slotId: "slot-1" },
    createdAt: 1,
    status: "pending",
    attempts: 0,
    ...overrides,
  };
}

const trainingPayload = {
  source_type: "freeform",
  source_reference_id: null,
  title: "Park run",
  performed_at: "2026-10-11T07:00:00Z",
  idempotency_key: "log-abc-123",
} as unknown as Parameters<typeof trainingLogCreateAdapter.send>[1];

beforeEach(() => {
  vi.clearAllMocks();
});

describe("explicit outbox adapter registry", () => {
  it("registers only the opted-in notification-triggering commands", () => {
    expect(registeredOutboxCommandKinds().sort()).toEqual([
      "booking.approve",
      "booking.reject",
      "booking.request",
      "journal_comment.delete",
      "journal_comment.save",
      "training_log.create",
    ]);
    expect(getOutboxCommandAdapter("workout.update")).toBeUndefined();
    expect(getOutboxCommandAdapter("message.send")).toBeUndefined();
  });

  it("classifies booking request failures by status and code", () => {
    expect(bookingRequestAdapter.classify(new TypeError("offline")).category).toBe("transient");
    expect(bookingRequestAdapter.classify(apiError(503)).category).toBe("transient");
    expect(bookingRequestAdapter.classify(apiError(429)).category).toBe("transient");
    expect(bookingRequestAdapter.classify(apiError(401)).category).toBe("transient");
    expect(bookingRequestAdapter.classify(apiError(409, "slot_full"))).toEqual({
      category: "conflict",
      status: 409,
      code: "slot_full",
    });
    expect(bookingRequestAdapter.classify(apiError(409, "already_booked")).category).toBe("conflict");
    expect(bookingRequestAdapter.classify(apiError(422, "slot_in_past")).category).toBe("permanent");
    expect(
      bookingRequestAdapter.classify(apiError(403, "finance_allowance_exhausted")).category,
    ).toBe("permanent");
  });

  it("treats an already resolved booking as a conflict, never a replay", () => {
    expect(bookingApproveAdapter.classify(apiError(409, "booking_not_pending")).category).toBe(
      "conflict",
    );
    expect(bookingApproveAdapter.classify(apiError(404, "not_found")).category).toBe("permanent");
  });

  it("treats an already logged training source as a conflict", () => {
    expect(
      trainingLogCreateAdapter.classify(apiError(409, "training_log_source_already_logged"))
        .category,
    ).toBe("conflict");
    expect(
      trainingLogCreateAdapter.classify(apiError(409, "idempotency_key_conflict")).category,
    ).toBe("conflict");
  });

  it("derives idempotency keys per command", () => {
    expect(bookingRequestAdapter.idempotencyKey({ slotId: "slot-1" })).toBeNull();
    expect(trainingLogCreateAdapter.idempotencyKey(trainingPayload)).toBe("log-abc-123");
  });

  it("sends the operation id and the pinned organization", async () => {
    vi.mocked(createBooking).mockResolvedValue({ id: "booking-1" } as never);
    vi.mocked(approveBooking).mockResolvedValue({ id: "booking-1" } as never);
    vi.mocked(createTrainingLogEntry).mockResolvedValue({ id: "entry-1" } as never);
    const context = { idempotencyKey: "op-1", organizationSlug: "atlas" };

    await bookingRequestAdapter.send("token", { slotId: "slot-1" }, context);
    await bookingApproveAdapter.send("token", { bookingId: "booking-1", adminMessage: "Hi" }, context);
    await trainingLogCreateAdapter.send("token", trainingPayload, {
      idempotencyKey: "log-abc-123",
      organizationSlug: "atlas",
    });

    expect(createBooking).toHaveBeenCalledWith("token", "slot-1", {
      clientOperationId: "op-1",
      organizationSlug: "atlas",
    });
    expect(approveBooking).toHaveBeenCalledWith("token", "booking-1", "Hi", {
      clientOperationId: "op-1",
      organizationSlug: "atlas",
    });
    expect(createTrainingLogEntry).toHaveBeenCalledWith(
      "token",
      expect.objectContaining({ idempotency_key: "log-abc-123" }),
      { organizationSlug: "atlas" },
    );
  });
});

describe("submitOutboxCommand", () => {
  const send = vi.fn();
  const adapter: OutboxCommandAdapter = {
    ...bookingRequestAdapter,
    send,
  } as OutboxCommandAdapter;
  const lookup = (kind: string) => (kind === "booking.request" ? adapter : undefined);
  const base = {
    token: "token",
    ownerUserId: "user-1",
    organizationSlug: "atlas",
    kind: "booking.request" as const,
    payload: { slotId: "slot-1" },
    lookup,
  };

  it("queues without sending while offline", async () => {
    const store = createMemoryCommandStore();

    const outcome = await submitOutboxCommand({ ...base, store, online: false });

    expect(outcome.status).toBe("queued");
    expect(send).not.toHaveBeenCalled();
    expect(store.snapshot()).toEqual([
      expect.objectContaining({ kind: "booking.request", status: "pending", ownerUserId: "user-1" }),
    ]);
  });

  it("removes the record once delivered", async () => {
    const store = createMemoryCommandStore();
    send.mockResolvedValue({ id: "booking-1" });

    const outcome = await submitOutboxCommand({ ...base, store, online: true });

    expect(outcome).toMatchObject({ status: "delivered", result: { id: "booking-1" } });
    expect(store.snapshot()).toEqual([]);
    const [, , context] = send.mock.calls[0];
    expect(context).toEqual({ idempotencyKey: outcome.operationId, organizationSlug: "atlas" });
  });

  it("keeps a transient failure pending for automatic replay", async () => {
    const store = createMemoryCommandStore();
    send.mockRejectedValue(new TypeError("network"));

    const outcome = await submitOutboxCommand({ ...base, store, online: true });

    expect(outcome.status).toBe("queued");
    expect(store.snapshot()).toEqual([
      expect.objectContaining({ status: "pending", attempts: 1, failure: { category: "transient" } }),
    ]);
  });

  it("rethrows a foreground conflict and keeps nothing queued", async () => {
    const store = createMemoryCommandStore();
    const conflict = apiError(409, "slot_full");
    send.mockRejectedValue(conflict);

    await expect(submitOutboxCommand({ ...base, store, online: true })).rejects.toBe(conflict);
    expect(store.snapshot()).toEqual([]);
  });

  it("sends directly when no durable store is available", async () => {
    send.mockResolvedValue({ id: "booking-1" });

    const outcome = await submitOutboxCommand({ ...base, store: null, online: false });

    expect(outcome.status).toBe("delivered");
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("refuses unregistered commands", async () => {
    await expect(
      submitOutboxCommand({
        ...base,
        kind: "booking.reject",
        store: createMemoryCommandStore(),
      }),
    ).rejects.toThrow(/No outbox adapter/);
  });
});

describe("reconcileOutboxCommands", () => {
  it("replays only the owner's pending operations, oldest first, with their original keys", async () => {
    const send = vi.fn().mockResolvedValue({ id: "ok" });
    const adapter = { ...bookingRequestAdapter, send } as OutboxCommandAdapter;
    const store = createMemoryCommandStore([
      queued({ operationId: "op-2", createdAt: 2 }),
      queued({ operationId: "other", ownerUserId: "user-2", createdAt: 0 }),
      queued({ operationId: "failed", status: "failed", createdAt: 0 }),
      queued({ operationId: "op-1", createdAt: 1 }),
    ]);

    await reconcileOutboxCommands({ token: "token", ownerUserId: "user-1", lookup: () => adapter, store });

    expect(send.mock.calls.map(([, , context]) => context.idempotencyKey)).toEqual(["op-1", "op-2"]);
    expect(store.snapshot().map((operation) => operation.operationId).sort()).toEqual([
      "failed",
      "other",
    ]);
  });

  it("parks conflicts as failed, continues, and stops at the first transient failure", async () => {
    const send = vi
      .fn()
      .mockRejectedValueOnce(apiError(409, "already_booked"))
      .mockRejectedValueOnce(apiError(503))
      .mockResolvedValue({ id: "never" });
    const adapter = { ...bookingRequestAdapter, send } as OutboxCommandAdapter;
    const store = createMemoryCommandStore([
      queued({ operationId: "op-1", createdAt: 1 }),
      queued({ operationId: "op-2", createdAt: 2 }),
      queued({ operationId: "op-3", createdAt: 3 }),
    ]);

    await reconcileOutboxCommands({ token: "token", ownerUserId: "user-1", lookup: () => adapter, store });

    expect(send).toHaveBeenCalledTimes(2);
    const byId = Object.fromEntries(store.snapshot().map((operation) => [operation.operationId, operation]));
    expect(byId["op-1"]).toMatchObject({
      status: "failed",
      failure: { category: "conflict", code: "already_booked" },
    });
    expect(byId["op-2"]).toMatchObject({ status: "pending", attempts: 1 });
    expect(byId["op-3"]).toMatchObject({ status: "pending", attempts: 0 });
  });

  it("never replays a kind without a registered adapter", async () => {
    const store = createMemoryCommandStore([queued({ kind: "workout.delete" })]);

    await reconcileOutboxCommands({
      token: "token",
      ownerUserId: "user-1",
      lookup: getOutboxCommandAdapter,
      store,
    });

    expect(store.snapshot()[0]).toMatchObject({
      status: "failed",
      failure: { category: "permanent", code: "unsupported_operation" },
    });
  });

  it("retries a failed operation with the same idempotency key", () => {
    const failed = queued({
      status: "failed",
      attempts: 2,
      failure: { category: "conflict", status: 409, code: "slot_full" },
    });

    expect(prepareCommandRetry(failed)).toMatchObject({
      operationId: "op-1",
      status: "pending",
      attempts: 2,
      failure: undefined,
    });
  });
});
