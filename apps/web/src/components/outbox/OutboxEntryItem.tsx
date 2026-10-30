"use client";

import { OutboxFailureControls } from "@/components/outbox/OutboxFailureControls";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import type { OutboxEntry } from "@/lib/outbox-snapshot";
import { clockFormat } from "@/lib/clock";

/** One queued or failed outbox operation, with Retry / Discard when it failed. */
export function OutboxEntryItem({
  entry,
  onRetry,
  onDiscard,
}: {
  entry: OutboxEntry;
  onRetry: (entry: OutboxEntry) => Promise<void>;
  onDiscard: (entry: OutboxEntry) => Promise<void>;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const queuedAt = clockFormat(locale, { dateStyle: "short", timeStyle: "short" }).format(entry.createdAt);

  return (
    <li className="rounded-2xl p-3" style={{ background: "var(--card)", border: "1px solid var(--border-strong)" }}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {i18n(entry.labelKey)}
        </span>
        <span className="text-[11px]" style={{ color: "var(--dim)" }}>
          {i18n("outboxQueuedAt", { time: queuedAt })}
        </span>
      </div>
      {entry.detail ? (
        <p className="mt-1 break-words text-xs [overflow-wrap:anywhere]" style={{ color: "var(--text-soft)" }} data-user-text>
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
          <OutboxFailureControls failure={entry.failure} onRetry={() => onRetry(entry)} onDiscard={() => onDiscard(entry)} />
        </div>
      ) : null}
    </li>
  );
}
