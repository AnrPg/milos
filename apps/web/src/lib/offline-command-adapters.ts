import { approveBooking, createBooking, rejectBooking, type ScheduleBooking } from "@/api/schedule";
import {
  createTrainingLogEntry,
  type CreateTrainingLogRequest,
  type TrainingLogEntry,
} from "@/api/training-log";
import {
  classifyWith,
  type OutboxCommandAdapter,
  type OutboxCommandKind,
} from "@/lib/offline-command-outbox";

/**
 * The explicit ADR-110 registry of non-message commands that may be queued
 * offline. Each entry is backed by a server-side idempotency and conflict
 * policy in its owning context; adding a command here without that policy is
 * forbidden. There is deliberately no fallback for unregistered kinds.
 */

export type BookingRequestPayload = { slotId: string; label?: string | null };

export type BookingResolutionPayload = {
  bookingId: string;
  adminMessage?: string | null;
  label?: string | null;
};

export type TrainingLogCreatePayload = CreateTrainingLogRequest;

export const bookingRequestAdapter: OutboxCommandAdapter<BookingRequestPayload, ScheduleBooking> = {
  kind: "booking.request",
  labelKey: "outboxKindBookingRequest",
  idempotencyKey: () => null,
  send: (token, payload, { idempotencyKey, organizationSlug }) =>
    createBooking(token, payload.slotId, { clientOperationId: idempotencyKey, organizationSlug }),
  // The class filled up, the user already holds a booking, or the key was
  // reused: the server state moved on, so surface it instead of replaying.
  classify: classifyWith(["slot_full", "already_booked", "idempotency_key_conflict"], ["slot_in_past"]),
  describe: (payload) => payload.label ?? null,
};

function resolutionAdapter(
  kind: Extract<OutboxCommandKind, "booking.approve" | "booking.reject">,
): OutboxCommandAdapter<BookingResolutionPayload, ScheduleBooking> {
  const resolve = kind === "booking.approve" ? approveBooking : rejectBooking;
  return {
    kind,
    labelKey: kind === "booking.approve" ? "outboxKindBookingApprove" : "outboxKindBookingReject",
    idempotencyKey: () => null,
    send: (token, payload, { idempotencyKey, organizationSlug }) =>
      resolve(token, payload.bookingId, payload.adminMessage ?? undefined, {
        clientOperationId: idempotencyKey,
        organizationSlug,
      }),
    // Another admin, the member, or the timeout resolved it first: never replay.
    classify: classifyWith(["booking_not_pending", "slot_full", "idempotency_key_conflict"]),
    describe: (payload) => payload.label ?? null,
  };
}

export const bookingApproveAdapter = resolutionAdapter("booking.approve");
export const bookingRejectAdapter = resolutionAdapter("booking.reject");

export const trainingLogCreateAdapter: OutboxCommandAdapter<
  TrainingLogCreatePayload,
  TrainingLogEntry
> = {
  kind: "training_log.create",
  labelKey: "outboxKindTrainingLog",
  // ADR-108 already carries a client idempotency key; reuse it so a double
  // submit from the form and an outbox replay converge on one entry.
  idempotencyKey: (payload) => payload.idempotency_key,
  send: (token, payload, { idempotencyKey, organizationSlug }) =>
    createTrainingLogEntry(token, { ...payload, idempotency_key: idempotencyKey }, { organizationSlug }),
  classify: classifyWith([
    "training_log_source_already_logged",
    "training_log_already_counted",
    "idempotency_key_conflict",
  ]),
  describe: (payload) => payload.title ?? null,
};

const REGISTERED_ADAPTERS = [
  bookingRequestAdapter,
  bookingApproveAdapter,
  bookingRejectAdapter,
  trainingLogCreateAdapter,
] as const;

const REGISTRY: ReadonlyMap<string, OutboxCommandAdapter> = new Map(
  REGISTERED_ADAPTERS.map((adapter) => [adapter.kind, adapter as OutboxCommandAdapter]),
);

export function getOutboxCommandAdapter(kind: string): OutboxCommandAdapter | undefined {
  return REGISTRY.get(kind);
}

export function registeredOutboxCommandKinds(): string[] {
  return [...REGISTRY.keys()];
}
