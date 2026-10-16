"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import { OutboxEntryItem } from "@/components/outbox/OutboxEntryItem";
import { useOutbox } from "@/components/outbox/use-outbox";

/**
 * Εγώ › Ρυθμίσεις › Συγχρονισμός offline (mockup «settings»): whether
 * everything this device saved has reached the server, what still waits,
 * what failed (Retry / Discard), and a way to sync now.
 */
export function OutboxSettingsCard() {
  const t = useTranslations("Profile");
  const { userId, snapshot, total, retry, discard, syncNow } = useOutbox();
  const online = useOnline();
  if (!userId) return null;

  const failed = snapshot.failed.length;
  const pending = snapshot.pending.length;
  const [label, tone] =
    failed > 0
      ? [t("syncFailed", { count: failed }), "var(--danger)"]
      : !online
        ? [t("syncOffline"), "var(--warning)"]
        : pending > 0
          ? [t("syncPending", { count: pending }), "var(--warning)"]
          : [t("syncAllDone"), "var(--success)"];

  return (
    <section
      aria-labelledby="sync-heading"
      className="space-y-3 rounded-[2.4rem] p-8"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="sync-heading" className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
          {t("syncTitle")}
        </h2>
        <span
          aria-live="polite"
          className="rounded-full px-3 py-1 text-xs font-semibold"
          style={{ color: tone, border: `1px solid ${tone}` }}
        >
          {label}
        </span>
      </div>
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("syncDescription")}</p>
      {total > 0 ? (
        <ul className="space-y-2">
          {[...snapshot.failed, ...snapshot.pending].map((entry) => (
            <OutboxEntryItem key={entry.operationId} entry={entry} onRetry={retry} onDiscard={discard} />
          ))}
        </ul>
      ) : null}
      {pending > 0 && online ? (
        <button
          type="button"
          onClick={() => syncNow()}
          className="min-h-11 rounded-xl px-5 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("syncNow")}
        </button>
      ) : null}
    </section>
  );
}

function useOnline() {
  const [online, setOnline] = useState(true);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    queueMicrotask(update);
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);
  return online;
}
