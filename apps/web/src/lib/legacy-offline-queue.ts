import { useExecutionStore } from "@/stores/execution";

/**
 * One-release migration for the retired IndexedDB check-off queue.
 *
 * Earlier builds queued offline check-offs in IndexedDB. Progress now lives
 * in the persisted execution store and syncs from there, so any check-offs
 * still waiting in the old queue are folded into local progress (marked
 * pending, so the normal sync sends them) and removed from the queue.
 * Remove this module once that release has been out long enough.
 */
const DATABASE = "palee-offline-execution-v1";
const STORE = "progress-operations";

type LegacyCheckoff = {
  operationId: string;
  executionId: string;
  createdAt: number;
  add: string[];
  remove: string[];
};

function openExisting(): Promise<IDBDatabase | null> {
  return new Promise((resolve) => {
    if (typeof indexedDB === "undefined") {
      resolve(null);
      return;
    }

    let created = false;
    const request = indexedDB.open(DATABASE);
    request.onupgradeneeded = () => {
      // The database did not exist: nothing to migrate, and don't leave one behind.
      created = true;
    };
    request.onsuccess = () => {
      const database = request.result;
      if (created || !database.objectStoreNames.contains(STORE)) {
        database.close();
        if (created) indexedDB.deleteDatabase(DATABASE);
        resolve(null);
        return;
      }
      resolve(database);
    };
    request.onerror = () => resolve(null);
  });
}

function takeQueued(database: IDBDatabase, executionId: string): Promise<LegacyCheckoff[]> {
  return new Promise((resolve) => {
    const tx = database.transaction(STORE, "readwrite");
    const store = tx.objectStore(STORE);
    const request = store.getAll();
    let items: LegacyCheckoff[] = [];
    request.onsuccess = () => {
      items = (request.result as LegacyCheckoff[])
        .filter((item) => item.executionId === executionId)
        .sort((a, b) => a.createdAt - b.createdAt);
      items.forEach((item) => store.delete(item.operationId));
    };
    tx.oncomplete = () => resolve(items);
    tx.onerror = () => resolve([]);
    tx.onabort = () => resolve([]);
  });
}

/** Replays `add`/`remove` operations, oldest first, on a check-off list. */
export function applyLegacyCheckoffs(checked: string[], items: Pick<LegacyCheckoff, "add" | "remove">[]) {
  const result = new Set(checked);
  for (const item of items) {
    item.remove.forEach((id) => result.delete(id));
    item.add.forEach((id) => result.add(id));
  }
  return [...result];
}

export async function adoptLegacyCheckoffs(executionId: string): Promise<boolean> {
  try {
    const database = await openExisting();
    if (!database) return false;

    const items = await takeQueued(database, executionId);
    database.close();
    if (items.length === 0) return false;

    const store = useExecutionStore.getState();
    if (store.executionId !== executionId || store.status === "completed") return false;

    const next = applyLegacyCheckoffs(store.checkedExerciseIds, items);
    store.setCheckedExerciseIds(next);
    store.setPendingSync(true);
    return true;
  } catch {
    return false;
  }
}
