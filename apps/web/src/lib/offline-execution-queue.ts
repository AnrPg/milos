import {
  fetchExecution,
  type ExecutionProgressPayload,
  updateExecutionProgress,
  type WorkoutExecution,
} from "@/api/executions";
import { ApiError } from "@/api/client";

const DATABASE = "milos-offline-execution-v1";
const STORE = "progress-operations";

export type QueuedCheckoff = {
  operationId: string;
  executionId: string;
  createdAt: number;
  payload: ExecutionProgressPayload;
  add: string[];
  remove: string[];
};

function openDatabase() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE)) {
        const store = database.createObjectStore(STORE, { keyPath: "operationId" });
        store.createIndex("execution-created", ["executionId", "createdAt"]);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function transaction<T>(
  mode: IDBTransactionMode,
  run: (store: IDBObjectStore, resolve: (value: T) => void, reject: (error: unknown) => void) => void,
) {
  const database = await openDatabase();
  return new Promise<T>((resolve, reject) => {
    const tx = database.transaction(STORE, mode);
    run(tx.objectStore(STORE), resolve, reject);
    tx.oncomplete = () => database.close();
    tx.onerror = () => reject(tx.error);
  });
}

export async function queueOfflineCheckoff(
  executionId: string,
  payload: ExecutionProgressPayload,
  previous: string[],
  next: string[],
) {
  const previousSet = new Set(previous);
  const nextSet = new Set(next);
  const item: QueuedCheckoff = {
    operationId: payload.operation_id,
    executionId,
    createdAt: Date.now(),
    payload,
    add: next.filter((id) => !previousSet.has(id)),
    remove: previous.filter((id) => !nextSet.has(id)),
  };

  await transaction<void>("readwrite", (store, resolve, reject) => {
    const request = store.put(item);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

async function queuedForExecution(executionId: string) {
  return transaction<QueuedCheckoff[]>("readonly", (store, resolve, reject) => {
    const index = store.index("execution-created");
    const range = IDBKeyRange.bound([executionId, 0], [executionId, Number.MAX_SAFE_INTEGER]);
    const request = index.getAll(range);
    request.onsuccess = () => resolve(request.result as QueuedCheckoff[]);
    request.onerror = () => reject(request.error);
  });
}

async function removeQueued(operationId: string) {
  return transaction<void>("readwrite", (store, resolve, reject) => {
    const request = store.delete(operationId);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

export function rebaseQueuedCheckoff(
  item: QueuedCheckoff,
  current: WorkoutExecution,
): ExecutionProgressPayload {
  const checked = new Set(current.checked_exercise_ids);
  item.remove.forEach((id) => checked.delete(id));
  item.add.forEach((id) => checked.add(id));

  return {
    ...item.payload,
    operation_id: item.operationId,
    expected_version: current.lock_version,
    checked_exercise_ids: [...checked],
    current_segment_index: current.current_segment_index,
    status: current.status === "paused" ? "paused" : "active",
    segment_started_at_utc: current.segment_started_at_utc,
    paused_elapsed_ms: current.paused_elapsed_ms,
    resume_countdown_ends_at_utc: current.resume_countdown_ends_at_utc,
    total_elapsed_ms: Math.max(current.total_elapsed_ms, item.payload.total_elapsed_ms),
    section_elapsed_ms: mergeMaximums(current.section_elapsed_ms, item.payload.section_elapsed_ms),
    segment_cycle_counts: mergeMaximums(
      current.segment_cycle_counts,
      item.payload.segment_cycle_counts,
    ),
    section_scores: current.section_scores,
  };
}

function mergeMaximums(left: Record<string, number>, right: Record<string, number>) {
  const result = { ...left };
  Object.entries(right).forEach(([key, value]) => {
    result[key] = Math.max(result[key] ?? 0, value);
  });
  return result;
}

export async function reconcileOfflineCheckoffs(
  token: string,
  executionId: string,
  onProgress: (execution: WorkoutExecution) => void,
) {
  const queued = await queuedForExecution(executionId);
  if (queued.length === 0) return;

  let current = await fetchExecution(token, executionId);

  for (const item of queued) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        current = await updateExecutionProgress(token, executionId, rebaseQueuedCheckoff(item, current));
        await removeQueued(item.operationId);
        onProgress(current);
        break;
      } catch (error) {
        if (error instanceof ApiError && error.status === 409) {
          current = await fetchExecution(token, executionId);
          continue;
        }
        throw error;
      }
    }
  }
}

export function isOfflineFailure(error: unknown) {
  return typeof navigator !== "undefined" && (!navigator.onLine || error instanceof TypeError);
}
