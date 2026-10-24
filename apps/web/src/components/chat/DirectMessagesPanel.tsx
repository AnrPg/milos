"use client";

import { useState } from "react";

import { InboxView } from "@/components/chat/inbox/InboxView";
import type { InboxSegment } from "@/components/chat/inbox/inbox-model";
import { Dialog } from "@/components/ui/Dialog";
import { useUiTranslations } from "@/i18n/ui";

/**
 * The console's message drawer (TopNav): the same inbox as `/messages`
 * (ADR-196), opened over the current screen.
 */
export function DirectMessagesPanel({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  const [segment, setSegment] = useState<InboxSegment>("all");
  const [threadId, setThreadId] = useState<string | null>(null);

  return (
    <Dialog
      onClose={onClose}
      bare
      variant="drawer"
      size="md"
      ariaLabel={i18n("chat2ced57f")}
      panelStyle={{ background: "var(--panel-muted)", borderColor: "var(--border-strong)" }}
    >
      <InboxView
        segment={segment}
        onSegmentChange={setSegment}
        threadId={threadId}
        onThreadChange={setThreadId}
        onNavigate={onClose}
        heading={
          <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {i18n("chat2ced57f")}
          </span>
        }
        end={
          <button
            type="button"
            onClick={onClose}
            aria-label={i18n("closebbfa773")}
            className="flex h-11 w-11 items-center justify-center text-lg leading-none"
            style={{ color: "var(--dim)" }}
          >
            ✕
          </button>
        }
      />
    </Dialog>
  );
}
