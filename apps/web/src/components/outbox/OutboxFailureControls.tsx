"use client";

import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";
import { describeOutboxFailure, type OutboxFailure } from "@/lib/outbox-failure";

type OutboxFailureControlsProps = {
  failure?: OutboxFailure;
  onRetry: () => void | Promise<void>;
  onDiscard: () => void | Promise<void>;
  /** i18n key for the discard confirmation question. */
  confirmKey?: string;
  align?: "start" | "end";
};

/**
 * Failure reason plus explicit Retry (same idempotency key) and Discard
 * (two-step confirmation) for a permanently failed outbox operation (ADR-102).
 */
export function OutboxFailureControls({
  failure,
  onRetry,
  onDiscard,
  confirmKey = "outboxDiscardConfirm",
  align = "start",
}: OutboxFailureControlsProps) {
  const i18n = useUiTranslations();
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  const run = async (action: () => void | Promise<void>) => {
    setBusy(true);
    try {
      await action();
    } finally {
      setBusy(false);
      setConfirming(false);
    }
  };

  const buttonClass =
    "min-h-8 rounded-full px-3 py-1 text-xs font-semibold transition-opacity disabled:opacity-50";

  return (
    <div className={"flex flex-col gap-1.5 " + (align === "end" ? "items-end text-end" : "items-start")}>
      <p className="text-xs leading-5" style={{ color: "var(--danger)" }}>
        {describeOutboxFailure(failure, i18n)}
        {failure?.category === "conflict" ? ` ${i18n("outboxConflictHint")}` : ""}
      </p>
      {confirming ? (
        <div className="flex flex-wrap items-center gap-2" role="group" aria-live="polite">
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>
            {i18n(confirmKey)}
          </span>
          <button
            type="button"
            className={buttonClass}
            style={{ background: "var(--danger)", color: "var(--primary-contrast)" }}
            disabled={busy}
            onClick={() => void run(onDiscard)}
          >
            {i18n("outboxDiscardConfirmAction")}
          </button>
          <button
            type="button"
            className={buttonClass}
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            disabled={busy}
            onClick={() => setConfirming(false)}
          >
            {i18n("outboxKeep")}
          </button>
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            className={buttonClass}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={busy}
            onClick={() => void run(onRetry)}
          >
            {i18n("outboxRetry")}
          </button>
          <button
            type="button"
            className={buttonClass}
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            disabled={busy}
            onClick={() => setConfirming(true)}
          >
            {i18n("outboxDiscard")}
          </button>
        </div>
      )}
    </div>
  );
}
