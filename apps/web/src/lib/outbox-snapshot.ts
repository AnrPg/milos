import type { QueuedCommandOperation } from "@/lib/offline-command-outbox";
import type { QueuedMessageOperation } from "@/lib/offline-message-outbox";
import type { OutboxFailure } from "@/lib/outbox-failure";

/**
 * A device-outbox entry as presented in the global outbox panel, independent
 * of whether it is a chat message (ADR-067) or a registered command (ADR-110).
 */
export type OutboxEntry = {
  source: "message" | "command";
  operationId: string;
  kind: string;
  labelKey: string;
  detail: string | null;
  createdAt: number;
  attempts: number;
  status: "pending" | "failed";
  failure?: OutboxFailure;
};

export type OutboxSnapshot = {
  pending: OutboxEntry[];
  failed: OutboxEntry[];
};

const MESSAGE_PREVIEW_LENGTH = 80;

export function messageEntry(operation: QueuedMessageOperation): OutboxEntry {
  const body = operation.body.trim();
  return {
    source: "message",
    operationId: operation.operationId,
    kind: "message.send",
    labelKey: "outboxKindMessage",
    detail:
      body.length > MESSAGE_PREVIEW_LENGTH ? `${body.slice(0, MESSAGE_PREVIEW_LENGTH - 1)}…` : body,
    createdAt: operation.createdAt,
    attempts: operation.attempts,
    status: operation.status,
    failure: operation.failure,
  };
}

export function commandEntry(
  operation: QueuedCommandOperation,
  describe: (operation: QueuedCommandOperation) => { labelKey: string; detail: string | null } | null,
): OutboxEntry {
  const description = describe(operation);
  return {
    source: "command",
    operationId: operation.operationId,
    kind: operation.kind,
    labelKey: description?.labelKey ?? "outboxKindUnknown",
    detail: description?.detail ?? null,
    createdAt: operation.createdAt,
    attempts: operation.attempts,
    status: operation.status,
    failure: operation.failure,
  };
}

export function buildOutboxSnapshot(entries: OutboxEntry[]): OutboxSnapshot {
  const sorted = [...entries].sort((left, right) => left.createdAt - right.createdAt);
  return {
    pending: sorted.filter((entry) => entry.status === "pending"),
    failed: sorted.filter((entry) => entry.status === "failed"),
  };
}
