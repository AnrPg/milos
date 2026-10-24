"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { listMyExecutions } from "@/api/executions";
import { useSession } from "@/components/session-provider";
import { ShareExportDialog } from "@/components/share-export/ShareExportDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { buildExecutionHistoryDocument } from "@/lib/document-export";

/**
 * Export of every completed workout as text, PDF or a share. It lives under
 * Vault's training history, the one place the history is (ANR 2026-10-24).
 */
export function HistoryExportButton() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const shareExport = useShareExport();
  const { tokens } = useSession();
  const [open, setOpen] = useState(false);

  const history = useQuery({
    queryKey: ["executions", "export-all"],
    enabled: Boolean(tokens?.access_token && open),
    queryFn: async () => (await listMyExecutions(tokens!.access_token)).filter((execution) => execution.status === "completed"),
  });
  const working = open && history.isPending;

  return (
    <>
      <button
        type="button"
        className="rounded-full px-4 py-2 text-sm font-semibold disabled:cursor-wait disabled:opacity-50"
        style={{ background: "var(--border)", color: "var(--text)" }}
        disabled={working}
        onClick={() => setOpen(true)}
      >
        {working ? shareExport.copy.working : i18n("exportFullWorkoutHistory")}
      </button>
      {open && history.data ? (
        <ShareExportDialog
          copy={shareExport.copy}
          document={buildExecutionHistoryDocument(history.data, shareExport.labels, uiLocale)}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}
