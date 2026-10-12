"use client";

import { useCallback, useEffect, useState } from "react";

import { InfoModal } from "@/components/InfoModal";
import { OutboxFailureControls } from "@/components/outbox/OutboxFailureControls";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
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
 * Global, per-user view of the device outbox (ADR-120): a compact status pill
 * while anything is waiting or failed, and a panel listing each operation with
 * its failure reason, Retry, and Discard.
 */
export function OutboxStatusPanel() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { currentUser, status } = useSession();
  const userId = status === "authenticated" ? currentUser?.id : undefined;
  const [raw, setRaw] = useState<RawOperations | null>(null);
  const [open, setOpen] = useState(false);

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

  if (!userId) return null;

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

  const formatTime = (timestamp: number) =>
    new Intl.DateTimeFormat(locale, { dateStyle: "short", timeStyle: "short" }).format(timestamp);

  const renderEntry = (entry: OutboxEntry) => (
    <li
      key={entry.operationId}
      className="rounded-2xl p-3"
      style={{ background: "var(--card)", border: "1px solid var(--border-strong)" }}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {i18n(entry.labelKey)}
        </span>
        <span className="text-[11px]" style={{ color: "var(--dim)" }}>
          {i18n("outboxQueuedAt", { time: formatTime(entry.createdAt) })}
        </span>
      </div>
      {entry.detail ? (
        <p
          className="mt-1 break-words text-xs [overflow-wrap:anywhere]"
          style={{ color: "var(--text-soft)" }}
          data-user-text
        >
          {entry.detail}
        </p>
      ) : null}
      {entry.attempts > 0 ? (
        <p className="mt-1 text-[11px]" style={{ color: "var(--dim)" }}>
          {i18n("outboxAttempts", { count: entry.attempts })}
        </p>
      ) : null}
      {entry.status === "failed" ? (
        <div className="mt-2">
          <OutboxFailureControls
            failure={entry.failure}
            onRetry={() => retry(entry)}
            onDiscard={() => discard(entry)}
          />
        </div>
      ) : null}
    </li>
  );

  return (
    <>
      {total > 0 ? (
        <button
          type="button"
          className="fixed bottom-[calc(1rem+env(safe-area-inset-bottom))] start-4 z-40 flex min-h-11 max-w-[calc(100vw-2rem)] items-center gap-2 rounded-full px-4 py-2 text-xs font-semibold shadow-lg"
          style={
            snapshot.failed.length > 0
              ? { background: "var(--danger)", color: "var(--primary-contrast)" }
              : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border-strong)" }
          }
          aria-haspopup="dialog"
          aria-label={i18n("outboxOpenPanel")}
          onClick={() => setOpen(true)}
        >
          <span aria-live="polite">
            {snapshot.failed.length > 0
              ? i18n("outboxIndicatorFailed", { count: snapshot.failed.length })
              : i18n("outboxIndicatorPending", { count: snapshot.pending.length })}
          </span>
        </button>
      ) : null}

      {open ? (
        <InfoModal title={i18n("outboxPanelTitle")} onClose={() => setOpen(false)}>
          <p>{i18n("outboxPanelDescription")}</p>
          {total === 0 ? <p>{i18n("outboxPanelEmpty")}</p> : null}
          {snapshot.failed.length > 0 ? (
            <section aria-labelledby="outbox-failed-heading" className="space-y-2">
              <h3 id="outbox-failed-heading" className="text-sm font-bold" style={{ color: "var(--text)" }}>
                {i18n("outboxFailedSection")}
              </h3>
              <ul className="max-h-[50vh] space-y-2 overflow-y-auto">{snapshot.failed.map(renderEntry)}</ul>
            </section>
          ) : null}
          {snapshot.pending.length > 0 ? (
            <section aria-labelledby="outbox-pending-heading" className="space-y-2">
              <h3 id="outbox-pending-heading" className="text-sm font-bold" style={{ color: "var(--text)" }}>
                {i18n("outboxPendingSection")}
              </h3>
              <ul className="max-h-[30vh] space-y-2 overflow-y-auto">{snapshot.pending.map(renderEntry)}</ul>
            </section>
          ) : null}
        </InfoModal>
      ) : null}
    </>
  );
}
