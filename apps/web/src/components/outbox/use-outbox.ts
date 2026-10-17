"use client";

import { useCallback, useEffect, useState } from "react";

import { useSession } from "@/components/session-provider";
import { requestOutboxSync } from "@/lib/device-outbox-db";
import { getOutboxCommandAdapter } from "@/lib/offline-command-adapters";
import {
  defaultCommandStore,
  discardOutboxCommand,
  OFFLINE_COMMAND_OUTBOX_EVENT,
  retryOutboxCommand,
  type QueuedCommandOperation,
} from "@/lib/offline-command-outbox";
import {
  discardQueuedMessageOperation,
  listQueuedMessageOperations,
  OFFLINE_MESSAGE_OUTBOX_EVENT,
  retryQueuedMessageOperation,
  type QueuedMessageOperation,
} from "@/lib/offline-message-outbox";
import {
  buildOutboxSnapshot,
  commandEntry,
  messageEntry,
  type OutboxEntry,
  type OutboxSnapshot,
} from "@/lib/outbox-snapshot";

type RawOperations = {
  messages: Map<string, QueuedMessageOperation>;
  commands: Map<string, QueuedCommandOperation>;
};

const EMPTY_SNAPSHOT: OutboxSnapshot = { pending: [], failed: [] };

function describeCommand(operation: QueuedCommandOperation) {
  const adapter = getOutboxCommandAdapter(operation.kind);
  if (!adapter) return null;
  return { labelKey: adapter.labelKey, detail: adapter.describe?.(operation.payload) ?? null };
}

async function loadOperations(userId: string): Promise<RawOperations> {
  const store = defaultCommandStore();
  const [messages, commands] = await Promise.all([
    listQueuedMessageOperations(userId).catch(() => [] as QueuedMessageOperation[]),
    store ? store.list(userId).catch(() => [] as QueuedCommandOperation[]) : Promise.resolve([]),
  ]);
  return {
    messages: new Map(messages.map((operation) => [operation.operationId, operation])),
    commands: new Map(commands.map((operation) => [operation.operationId, operation])),
  };
}

/**
 * The signed-in user's device outbox (ADR-120): what waits to sync, what
 * failed, and Retry / Discard. Shared by the global status pill and
 * Εγώ › Ρυθμίσεις › Συγχρονισμός offline.
 */
export function useOutbox() {
  const { currentUser, status } = useSession();
  const userId = status === "authenticated" ? currentUser?.id : undefined;
  const [raw, setRaw] = useState<RawOperations | null>(null);

  const refresh = useCallback(async () => {
    if (!userId || typeof indexedDB === "undefined") return;
    setRaw(await loadOperations(userId));
  }, [userId]);

  useEffect(() => {
    if (!userId) return;
    const handle = () => void refresh();
    queueMicrotask(handle);
    window.addEventListener(OFFLINE_MESSAGE_OUTBOX_EVENT, handle);
    window.addEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, handle);
    window.addEventListener("online", handle);
    window.addEventListener("offline", handle);
    return () => {
      window.removeEventListener(OFFLINE_MESSAGE_OUTBOX_EVENT, handle);
      window.removeEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, handle);
      window.removeEventListener("online", handle);
      window.removeEventListener("offline", handle);
    };
  }, [refresh, userId]);

  const snapshot = raw
    ? buildOutboxSnapshot([
        ...[...raw.messages.values()].map(messageEntry),
        ...[...raw.commands.values()].map((operation) => commandEntry(operation, describeCommand)),
      ])
    : EMPTY_SNAPSHOT;
  const total = snapshot.pending.length + snapshot.failed.length;

  const retry = async (entry: OutboxEntry) => {
    if (entry.source === "message") {
      const operation = raw?.messages.get(entry.operationId);
      if (operation) await retryQueuedMessageOperation(operation);
    } else {
      const operation = raw?.commands.get(entry.operationId);
      const store = defaultCommandStore();
      if (operation && store) await retryOutboxCommand(store, operation);
    }
    requestOutboxSync();
  };

  const discard = async (entry: OutboxEntry) => {
    if (entry.source === "message") {
      await discardQueuedMessageOperation(entry.operationId);
    } else {
      const store = defaultCommandStore();
      if (store) await discardOutboxCommand(store, entry.operationId);
    }
  };

  return { userId, snapshot, total, retry, discard, syncNow: requestOutboxSync };
}
