"use client";

import { useState } from "react";

import { InfoModal } from "@/components/InfoModal";
import { OutboxEntryItem } from "@/components/outbox/OutboxEntryItem";
import { useOutbox } from "@/components/outbox/use-outbox";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Global, per-user view of the device outbox (ADR-120): a compact status pill
 * while anything is waiting or failed, and a panel listing each operation with
 * its failure reason, Retry, and Discard.
 */
export function OutboxStatusPanel() {
  const i18n = useUiTranslations();
  const { userId, snapshot, total, retry, discard } = useOutbox();
  const [open, setOpen] = useState(false);

  if (!userId) return null;

  return (
    <>
      {total > 0 ? (
        <button
          type="button"
          className="fixed bottom-[calc(var(--bottom-float-inset)+1rem)] start-4 z-(--z-sticky) flex min-h-11 max-w-[calc(100vw-2rem)] items-center gap-2 rounded-full px-4 py-2 text-xs font-semibold shadow-lg"
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
              <ul className="max-h-[50vh] space-y-2 overflow-y-auto">{snapshot.failed.map((entry) => (
                  <OutboxEntryItem key={entry.operationId} entry={entry} onRetry={retry} onDiscard={discard} />
                ))}</ul>
            </section>
          ) : null}
          {snapshot.pending.length > 0 ? (
            <section aria-labelledby="outbox-pending-heading" className="space-y-2">
              <h3 id="outbox-pending-heading" className="text-sm font-bold" style={{ color: "var(--text)" }}>
                {i18n("outboxPendingSection")}
              </h3>
              <ul className="max-h-[30vh] space-y-2 overflow-y-auto">{snapshot.pending.map((entry) => (
                  <OutboxEntryItem key={entry.operationId} entry={entry} onRetry={retry} onDiscard={discard} />
                ))}</ul>
            </section>
          ) : null}
        </InfoModal>
      ) : null}
    </>
  );
}
