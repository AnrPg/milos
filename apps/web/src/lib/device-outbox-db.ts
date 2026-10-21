/**
 * Shared IndexedDB database for the per-device durable outbox (ADR-067,
 * ADR-120). Version 1 held only message operations; version 2 adds the
 * explicitly registered non-message command operations. Upgrades are
 * additive: existing stores are never dropped, so queued messages survive.
 */
export const DEVICE_OUTBOX_DATABASE = "palee-device-outbox-v1";
export const DEVICE_OUTBOX_VERSION = 2;
export const MESSAGE_OPERATIONS_STORE = "message-operations";
export const COMMAND_OPERATIONS_STORE = "command-operations";

export type DeviceOutboxStore = typeof MESSAGE_OPERATIONS_STORE | typeof COMMAND_OPERATIONS_STORE;

export function deviceOutboxAvailable() {
  return typeof indexedDB !== "undefined";
}

export function openDeviceOutboxDatabase() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    if (!deviceOutboxAvailable()) {
      reject(new Error("IndexedDB is unavailable"));
      return;
    }

    const request = indexedDB.open(DEVICE_OUTBOX_DATABASE, DEVICE_OUTBOX_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;

      if (!database.objectStoreNames.contains(MESSAGE_OPERATIONS_STORE)) {
        const store = database.createObjectStore(MESSAGE_OPERATIONS_STORE, { keyPath: "operationId" });
        store.createIndex("owner-created", ["ownerUserId", "createdAt"]);
        store.createIndex("owner-thread-created", ["ownerUserId", "threadId", "createdAt"]);
      }

      if (!database.objectStoreNames.contains(COMMAND_OPERATIONS_STORE)) {
        const store = database.createObjectStore(COMMAND_OPERATIONS_STORE, { keyPath: "operationId" });
        store.createIndex("owner-created", ["ownerUserId", "createdAt"]);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function deviceOutboxTransaction<T>(
  storeName: DeviceOutboxStore,
  mode: IDBTransactionMode,
  run: (store: IDBObjectStore, resolve: (value: T) => void, reject: (error: unknown) => void) => void,
) {
  const database = await openDeviceOutboxDatabase();
  return new Promise<T>((resolve, reject) => {
    const tx = database.transaction(storeName, mode);
    let result: T;
    run(
      tx.objectStore(storeName),
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

export function ownerCreatedRange(ownerUserId: string) {
  return IDBKeyRange.bound([ownerUserId, 0], [ownerUserId, Number.MAX_SAFE_INTEGER]);
}

export async function requestPersistentStorage() {
  if (typeof navigator === "undefined" || !navigator.storage?.persist) return;
  try {
    await navigator.storage.persist();
  } catch {
    // Best effort only. The outbox remains usable with normal browser storage.
  }
}

export const OUTBOX_SYNC_REQUESTED_EVENT = "palee:outbox-sync-requested";

/** Asks the root sync bridge to reconcile now (after an explicit retry). */
export function requestOutboxSync() {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(OUTBOX_SYNC_REQUESTED_EVENT));
}
