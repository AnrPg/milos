import { sendMessage, type ChatMessage, type MessageType } from "@/api/messaging";
import {
  deviceOutboxTransaction,
  MESSAGE_OPERATIONS_STORE,
  ownerCreatedRange,
  requestPersistentStorage,
} from "@/lib/device-outbox-db";
import { classifyDeliveryError, type OutboxFailure } from "@/lib/outbox-failure";

export const OFFLINE_MESSAGE_OUTBOX_EVENT = "milos:offline-message-outbox";

export type QueuedMessageStatus = "pending" | "failed";

export type QueuedMessageOperation = {
  operationId: string;
  ownerUserId: string;
  threadId: string;
  body: string;
  messageType: MessageType;
  createdAt: number;
  status: QueuedMessageStatus;
  attempts: number;
  /** Legacy free-text error from ADR-067 records; superseded by `failure`. */
  lastError?: string;
  failure?: OutboxFailure;
};

export type DisplayChatMessage = ChatMessage & {
  client_operation_id?: string | null;
  delivery_status: "sent" | QueuedMessageStatus;
  delivery_failure?: OutboxFailure;
};

type ReconcileOptions = {
  ownerUserId: string;
  operations: QueuedMessageOperation[];
  deliver: (operation: QueuedMessageOperation) => Promise<ChatMessage>;
  remove: (operationId: string) => Promise<void>;
  onDelivered?: (operation: QueuedMessageOperation, message: ChatMessage) => void;
};

function transaction<T>(
  mode: IDBTransactionMode,
  run: (
    store: IDBObjectStore,
    resolve: (value: T) => void,
    reject: (error: unknown) => void,
  ) => void,
) {
  return deviceOutboxTransaction<T>(MESSAGE_OPERATIONS_STORE, mode, run);
}

export async function queueMessageOperation(
  ownerUserId: string,
  threadId: string,
  body: string,
  messageType: MessageType,
) {
  await requestPersistentStorage();

  const operation: QueuedMessageOperation = {
    operationId: crypto.randomUUID(),
    ownerUserId,
    threadId,
    body,
    messageType,
    createdAt: Date.now(),
    status: "pending",
    attempts: 0,
  };

  await putOperation(operation);
  return operation;
}

export async function listQueuedMessageOperations(ownerUserId: string, threadId?: string) {
  return transaction<QueuedMessageOperation[]>("readonly", (store, resolve, reject) => {
    const index = store.index(threadId ? "owner-thread-created" : "owner-created");
    const range = threadId
      ? IDBKeyRange.bound(
          [ownerUserId, threadId, 0],
          [ownerUserId, threadId, Number.MAX_SAFE_INTEGER],
        )
      : ownerCreatedRange(ownerUserId);
    const request = index.getAll(range);
    request.onsuccess = () => resolve(request.result as QueuedMessageOperation[]);
    request.onerror = () => reject(request.error);
  });
}

async function putOperation(operation: QueuedMessageOperation) {
  return transaction<void>("readwrite", (store, resolve, reject) => {
    const request = store.put(operation);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

export async function removeQueuedMessageOperation(operationId: string) {
  return transaction<void>("readwrite", (store, resolve, reject) => {
    const request = store.delete(operationId);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

export async function recordMessageDeliveryFailure(
  operation: QueuedMessageOperation,
  error: unknown,
) {
  const updated = applyMessageDeliveryFailure(operation, error);
  await putOperation(updated);
  notifyOutboxChanged();
  return updated;
}

/**
 * Pure failure transition: transient failures stay pending for automatic
 * replay; permanent and conflict failures become `failed` and wait for an
 * explicit retry or discard (ADR-110).
 */
export function applyMessageDeliveryFailure(
  operation: QueuedMessageOperation,
  error: unknown,
): QueuedMessageOperation {
  const failure = classifyDeliveryError(error);
  return {
    ...operation,
    attempts: operation.attempts + 1,
    status: failure.category === "transient" ? "pending" : "failed",
    failure,
    lastError: undefined,
  };
}

/** Re-enqueues a failed message with its original operation id. */
export function prepareMessageRetry(operation: QueuedMessageOperation): QueuedMessageOperation {
  return { ...operation, status: "pending", failure: undefined, lastError: undefined };
}

export async function retryQueuedMessageOperation(operation: QueuedMessageOperation) {
  const retried = prepareMessageRetry(operation);
  await putOperation(retried);
  notifyOutboxChanged();
  return retried;
}

export async function discardQueuedMessageOperation(operationId: string) {
  await removeQueuedMessageOperation(operationId);
  notifyOutboxChanged();
}

export async function deliverQueuedMessage(token: string, operation: QueuedMessageOperation) {
  return sendMessage(
    token,
    operation.threadId,
    operation.body,
    operation.messageType,
    operation.operationId,
  );
}

export async function reconcileQueuedMessages({
  ownerUserId,
  operations,
  deliver,
  remove,
  onDelivered,
}: ReconcileOptions) {
  const owned = operations
    .filter((operation) => operation.ownerUserId === ownerUserId && operation.status === "pending")
    .sort((left, right) => left.createdAt - right.createdAt);

  for (const operation of owned) {
    const message = await deliver(operation);
    await remove(operation.operationId);
    onDelivered?.(operation, message);
  }
}

export async function reconcileStoredMessages(
  token: string,
  ownerUserId: string,
  onDelivered?: (operation: QueuedMessageOperation, message: ChatMessage) => void,
) {
  const operations = await listQueuedMessageOperations(ownerUserId);

  for (const operation of operations.filter((item) => item.status === "pending")) {
    try {
      const message = await deliverQueuedMessage(token, operation);
      await removeQueuedMessageOperation(operation.operationId);
      onDelivered?.(operation, message);
      notifyOutboxChanged(message);
    } catch (error) {
      const updated = await recordMessageDeliveryFailure(operation, error);
      // Stop on transient failures so ordering is preserved for the next sync.
      if (updated.status === "pending") break;
    }
  }
}

export function mergeMessagesWithPending(
  serverMessages: ChatMessage[],
  operations: QueuedMessageOperation[],
): DisplayChatMessage[] {
  const acknowledged = new Set(
    serverMessages.flatMap((message) => {
      const operationId = "client_operation_id" in message ? message.client_operation_id : null;
      return operationId ? [operationId] : [];
    }),
  );

  const delivered = serverMessages.map((message) => ({
    ...message,
    delivery_status: "sent" as const,
  }));
  const pending = operations
    .filter((operation) => !acknowledged.has(operation.operationId))
    .sort((left, right) => left.createdAt - right.createdAt)
    .map(operationToDisplayMessage);

  return [...delivered, ...pending];
}

export function operationToDisplayMessage(
  operation: QueuedMessageOperation,
): DisplayChatMessage {
  return {
    id: `pending:${operation.operationId}`,
    thread_id: operation.threadId,
    sender_id: operation.ownerUserId,
    body: operation.body,
    message_type: operation.messageType,
    client_operation_id: operation.operationId,
    inserted_at: new Date(operation.createdAt).toISOString(),
    delivery_status: operation.status,
    delivery_failure: operation.failure,
  } as DisplayChatMessage;
}

export function notifyOutboxChanged(message?: ChatMessage) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent(OFFLINE_MESSAGE_OUTBOX_EVENT, { detail: { message: message ?? null } }),
  );
}
