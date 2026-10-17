import {
  deleteJournalComment,
  saveJournalComment,
  type JournalComment,
  type JournalCommentDraft,
} from "@/api/journal-comments";
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
 * The explicit ADR-120 registry of non-message commands that may be queued
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
  // ADR-118 already carries a client idempotency key; reuse it so a double
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

export type JournalCommentDeletePayload = { id: string };

/**
 * ADR-140 §1: a comment save is an upsert by its client-generated id, so a
 * replay converges; the id doubles as the idempotency key.
 */
export const journalCommentSaveAdapter: OutboxCommandAdapter<JournalCommentDraft, JournalComment> = {
  kind: "journal_comment.save",
  labelKey: "outboxKindJournalComment",
  idempotencyKey: (payload) => payload.id,
  send: (token, payload) => saveJournalComment(token, payload),
  // The id was taken by another entry, or the entry is gone: replaying
  // cannot succeed.
  classify: classifyWith(["comment_conflict"], ["not_found"]),
  describe: (payload) => payload.body?.slice(0, 60) ?? null,
};

export const journalCommentDeleteAdapter: OutboxCommandAdapter<JournalCommentDeletePayload, void> = {
  kind: "journal_comment.delete",
  labelKey: "outboxKindJournalCommentDelete",
  idempotencyKey: (payload) => `delete:${payload.id}`,
  send: (token, payload) => deleteJournalComment(token, payload.id),
  classify: classifyWith([], ["not_found"]),
};

const REGISTERED_ADAPTERS = [
  bookingRequestAdapter,
  bookingApproveAdapter,
  bookingRejectAdapter,
  trainingLogCreateAdapter,
  journalCommentSaveAdapter,
  journalCommentDeleteAdapter,
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
