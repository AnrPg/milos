import {
  COMMAND_OPERATIONS_STORE,
  deviceOutboxAvailable,
  deviceOutboxTransaction,
  ownerCreatedRange,
  requestPersistentStorage,
} from "@/lib/device-outbox-db";
import { classifyDeliveryError, type OutboxFailure } from "@/lib/outbox-failure";

/**
 * Durable outbox for explicitly opted-in, notification-triggering commands
 * other than chat messages (ADR-120). Unlike a generic request queue, only
 * kinds with a registered adapter can be queued or replayed; each adapter
 * declares its idempotency key, retry classification, and conflict policy,
 * and its owning API context dedupes replays server-side.
 */

export const OFFLINE_COMMAND_OUTBOX_EVENT = "milos:offline-command-outbox";

export type OutboxCommandKind =
  | "booking.request"
  | "booking.approve"
  | "booking.reject"
  | "training_log.create"
  | "journal_comment.save"
  | "journal_comment.delete";

export type OutboxSendContext = {
  idempotencyKey: string;
  organizationSlug: string | null;
};

export type OutboxCommandAdapter<Payload = unknown, Result = unknown> = {
  kind: OutboxCommandKind;
  /** i18n key of the label shown in the outbox panel. */
  labelKey: string;
  /** Stable key derived from the payload, or `null` to mint a UUID once at enqueue. */
  idempotencyKey: (payload: Payload) => string | null;
  send: (token: string, payload: Payload, context: OutboxSendContext) => Promise<Result>;
  /** Transient vs permanent vs conflict, by HTTP status and error code. */
  classify: (error: unknown) => OutboxFailure;
  /** Short, user-provided context for the panel (never server data). */
  describe?: (payload: Payload) => string | null;
};

export type QueuedCommandStatus = "pending" | "failed";

export type QueuedCommandOperation = {
  /** Equals the idempotency key sent to the server. */
  operationId: string;
  kind: OutboxCommandKind | string;
  ownerUserId: string;
  organizationSlug: string | null;
  payload: unknown;
  createdAt: number;
  status: QueuedCommandStatus;
  attempts: number;
  failure?: OutboxFailure;
};

export type CommandOutboxStore = {
  put: (operation: QueuedCommandOperation) => Promise<void>;
  remove: (operationId: string) => Promise<void>;
  list: (ownerUserId: string) => Promise<QueuedCommandOperation[]>;
};

export type AdapterLookup = (kind: string) => OutboxCommandAdapter | undefined;

export const indexedDbCommandStore: CommandOutboxStore = {
  put: (operation) =>
    deviceOutboxTransaction<void>(COMMAND_OPERATIONS_STORE, "readwrite", (store, resolve, reject) => {
      const request = store.put(operation);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    }),
  remove: (operationId) =>
    deviceOutboxTransaction<void>(COMMAND_OPERATIONS_STORE, "readwrite", (store, resolve, reject) => {
      const request = store.delete(operationId);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    }),
  list: (ownerUserId) =>
    deviceOutboxTransaction<QueuedCommandOperation[]>(
      COMMAND_OPERATIONS_STORE,
      "readonly",
      (store, resolve, reject) => {
        const request = store.index("owner-created").getAll(ownerCreatedRange(ownerUserId));
        request.onsuccess = () => resolve(request.result as QueuedCommandOperation[]);
        request.onerror = () => reject(request.error);
      },
    ),
};

export function createMemoryCommandStore(
  initial: QueuedCommandOperation[] = [],
): CommandOutboxStore & { snapshot: () => QueuedCommandOperation[] } {
  const records = new Map(initial.map((operation) => [operation.operationId, operation]));
  return {
    put: async (operation) => {
      records.set(operation.operationId, operation);
    },
    remove: async (operationId) => {
      records.delete(operationId);
    },
    list: async (ownerUserId) =>
      [...records.values()]
        .filter((operation) => operation.ownerUserId === ownerUserId)
        .sort((left, right) => left.createdAt - right.createdAt),
    snapshot: () => [...records.values()],
  };
}

export function defaultCommandStore(): CommandOutboxStore | null {
  return deviceOutboxAvailable() ? indexedDbCommandStore : null;
}

export function notifyCommandOutboxChanged(detail: { kind?: string; delivered?: boolean } = {}) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(OFFLINE_COMMAND_OUTBOX_EVENT, { detail }));
}

function newOperationId() {
  return crypto.randomUUID();
}

export function buildCommandOperation(
  adapter: OutboxCommandAdapter,
  payload: unknown,
  ownerUserId: string,
  organizationSlug: string | null,
  now = Date.now(),
): QueuedCommandOperation {
  return {
    operationId: adapter.idempotencyKey(payload) ?? newOperationId(),
    kind: adapter.kind,
    ownerUserId,
    organizationSlug,
    payload,
    createdAt: now,
    status: "pending",
    attempts: 0,
  };
}

/** Pure failure transition shared by foreground submits and background replay. */
export function applyCommandFailure(
  operation: QueuedCommandOperation,
  failure: OutboxFailure,
): QueuedCommandOperation {
  return {
    ...operation,
    attempts: operation.attempts + 1,
    status: failure.category === "transient" ? "pending" : "failed",
    failure,
  };
}

export function prepareCommandRetry(operation: QueuedCommandOperation): QueuedCommandOperation {
  return { ...operation, status: "pending", failure: undefined };
}

export type SubmitCommandResult<Result> =
  | { status: "delivered"; result: Result; operationId: string }
  | { status: "queued"; operationId: string };

type SubmitOptions<Payload> = {
  token: string;
  ownerUserId: string;
  organizationSlug: string | null;
  kind: OutboxCommandKind;
  payload: Payload;
  lookup: AdapterLookup;
  store: CommandOutboxStore | null;
  online?: boolean;
};

/**
 * Records the command before attempting delivery, then sends it once.
 *
 * - Delivered: the record is removed and the server result returned.
 * - Transient failure (offline, 5xx, throttled): the record stays pending for
 *   automatic replay with the same idempotency key; returns `queued`.
 * - Permanent or conflict failure in the foreground: the user is present, so
 *   the record is removed and the error rethrown for inline handling.
 *
 * Without durable storage the command is sent directly (no offline queue).
 */
export async function submitOutboxCommand<Result, Payload = unknown>({
  token,
  ownerUserId,
  organizationSlug,
  kind,
  payload,
  lookup,
  store,
  online = typeof navigator === "undefined" ? true : navigator.onLine,
}: SubmitOptions<Payload>): Promise<SubmitCommandResult<Result>> {
  const adapter = lookup(kind) as OutboxCommandAdapter<Payload, Result> | undefined;
  if (!adapter) throw new Error(`No outbox adapter registered for ${kind}`);

  const operation = buildCommandOperation(
    adapter as OutboxCommandAdapter,
    payload,
    ownerUserId,
    organizationSlug,
  );
  const context = { idempotencyKey: operation.operationId, organizationSlug };

  const durable = store ? await persist(store, operation) : false;
  if (!durable) {
    const result = await adapter.send(token, payload, context);
    return { status: "delivered", result, operationId: operation.operationId };
  }

  notifyCommandOutboxChanged({ kind });
  if (!online) return { status: "queued", operationId: operation.operationId };

  try {
    const result = await adapter.send(token, payload, context);
    await store!.remove(operation.operationId);
    notifyCommandOutboxChanged({ kind, delivered: true });
    return { status: "delivered", result, operationId: operation.operationId };
  } catch (error) {
    const failure = adapter.classify(error);
    if (failure.category === "transient") {
      await store!.put(applyCommandFailure(operation, failure));
      notifyCommandOutboxChanged({ kind });
      return { status: "queued", operationId: operation.operationId };
    }

    await store!.remove(operation.operationId);
    notifyCommandOutboxChanged({ kind });
    throw error;
  }
}

async function persist(store: CommandOutboxStore, operation: QueuedCommandOperation) {
  try {
    await requestPersistentStorage();
    await store.put(operation);
    return true;
  } catch {
    // A blocked browser database must not block an online command.
    return false;
  }
}

type ReconcileOptions = {
  token: string;
  ownerUserId: string;
  lookup: AdapterLookup;
  store: CommandOutboxStore;
  onDelivered?: (operation: QueuedCommandOperation, result: unknown) => void;
};

/**
 * Replays the active user's pending commands in creation order. Only kinds
 * with a registered adapter are sent; anything else is parked as a permanent
 * `unsupported_operation` failure, never replayed generically. A transient
 * failure stops the run to preserve ordering for the next sync.
 */
export async function reconcileOutboxCommands({
  token,
  ownerUserId,
  lookup,
  store,
  onDelivered,
}: ReconcileOptions) {
  const operations = (await store.list(ownerUserId))
    .filter((operation) => operation.ownerUserId === ownerUserId && operation.status === "pending")
    .sort((left, right) => left.createdAt - right.createdAt);

  for (const operation of operations) {
    const adapter = lookup(operation.kind);
    if (!adapter) {
      await store.put(
        applyCommandFailure(operation, { category: "permanent", code: "unsupported_operation" }),
      );
      notifyCommandOutboxChanged({ kind: operation.kind });
      continue;
    }

    try {
      const result = await adapter.send(token, operation.payload, {
        idempotencyKey: operation.operationId,
        organizationSlug: operation.organizationSlug,
      });
      await store.remove(operation.operationId);
      onDelivered?.(operation, result);
      notifyCommandOutboxChanged({ kind: operation.kind, delivered: true });
    } catch (error) {
      const failure = adapter.classify(error);
      await store.put(applyCommandFailure(operation, failure));
      notifyCommandOutboxChanged({ kind: operation.kind });
      if (failure.category === "transient") break;
    }
  }
}

export async function retryOutboxCommand(store: CommandOutboxStore, operation: QueuedCommandOperation) {
  const retried = prepareCommandRetry(operation);
  await store.put(retried);
  notifyCommandOutboxChanged({ kind: operation.kind });
  return retried;
}

export async function discardOutboxCommand(store: CommandOutboxStore, operationId: string) {
  await store.remove(operationId);
  notifyCommandOutboxChanged();
}

/** Default classification for adapters that only add code-level policy. */
export function classifyWith(conflictCodes: readonly string[], permanentCodes: readonly string[] = []) {
  return (error: unknown) => classifyDeliveryError(error, { conflictCodes, permanentCodes });
}
