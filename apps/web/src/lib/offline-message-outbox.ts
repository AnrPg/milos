import { ApiError } from "@/api/client";
import { sendMessage, type ChatMessage, type MessageType } from "@/api/messaging";

const DATABASE = "milos-device-outbox-v1";
const STORE = "message-operations";

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
  lastError?: string;
};

export type DisplayChatMessage = ChatMessage & {
  client_operation_id?: string | null;
  delivery_status: "sent" | QueuedMessageStatus;
};

type ReconcileOptions = {
  ownerUserId: string;
  operations: QueuedMessageOperation[];
  deliver: (operation: QueuedMessageOperation) => Promise<ChatMessage>;
  remove: (operationId: string) => Promise<void>;
  onDelivered?: (operation: QueuedMessageOperation, message: ChatMessage) => void;
};

function openDatabase() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (database.objectStoreNames.contains(STORE)) return;

      const store = database.createObjectStore(STORE, { keyPath: "operationId" });
      store.createIndex("owner-created", ["ownerUserId", "createdAt"]);
      store.createIndex("owner-thread-created", ["ownerUserId", "threadId", "createdAt"]);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function transaction<T>(
  mode: IDBTransactionMode,
  run: (
    store: IDBObjectStore,
    resolve: (value: T) => void,
    reject: (error: unknown) => void,
  ) => void,
) {
  const database = await openDatabase();
  return new Promise<T>((resolve, reject) => {
    const tx = database.transaction(STORE, mode);
    let result: T;
    run(
      tx.objectStore(STORE),
      (value) => {
        result = value;
      },
      reject,
    );
    tx.oncomplete = () => {
      database.close();
      resolve(result);
    };
    tx.onerror = () => {
      database.close();
      reject(tx.error);
    };
    tx.onabort = () => {
      database.close();
      reject(tx.error);
    };
  });
}

async function requestPersistentStorage() {
  if (typeof navigator === "undefined" || !navigator.storage?.persist) return;
  try {
    await navigator.storage.persist();
  } catch {
    // Best effort only. The outbox remains usable with normal browser storage.
  }
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
    const indexName = threadId ? "owner-thread-created" : "owner-created";
    const index = store.index(indexName);
    const lower = threadId ? [ownerUserId, threadId, 0] : [ownerUserId, 0];
    const upper = threadId
      ? [ownerUserId, threadId, Number.MAX_SAFE_INTEGER]
      : [ownerUserId, Number.MAX_SAFE_INTEGER];
    const request = index.getAll(IDBKeyRange.bound(lower, upper));
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
  const permanent = error instanceof ApiError && error.status >= 400 && error.status < 500;
  const updated: QueuedMessageOperation = {
    ...operation,
    attempts: operation.attempts + 1,
    status: permanent ? "failed" : "pending",
    lastError: error instanceof Error ? error.message : "delivery failed",
  };
  await putOperation(updated);
  notifyOutboxChanged();
  return updated;
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
      await recordMessageDeliveryFailure(operation, error);
      if (!(error instanceof ApiError) || error.status >= 500) break;
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
  } as DisplayChatMessage;
}

export function notifyOutboxChanged(message?: ChatMessage) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent(OFFLINE_MESSAGE_OUTBOX_EVENT, { detail: { message: message ?? null } }),
  );
}
