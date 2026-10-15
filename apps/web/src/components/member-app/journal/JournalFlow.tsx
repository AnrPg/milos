"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";

import { fetchExecution } from "@/api/executions";
import { listTrainingLogEntries } from "@/api/training-log";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { EntryActions, SourceBadge } from "@/components/client/EntryActions";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay, formatTime } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { useWorkoutVault } from "@/components/client/use-workout-vault";
import { formatElapsed, historyEntries, type HistoryEntry } from "@/components/client/vault";
import { journalFlow } from "@/components/member-app/journal/journal-flow";
import { InAppShareDialog } from "@/components/share-export/InAppShareDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import {
  TRAINING_LOG_ENTRIES_KEY,
  TrainingLogDialog,
  TrainingLogEntryCard,
  type TrainingLogDialogState,
} from "@/components/training-log/TrainingLog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { buildExecutionDocument, renderText } from "@/lib/document-export";

/**
 * Ημερολόγιο › Ροή (brief §7.7, ADR-137): everything the member did, newest
 * first and grouped by day: finished executions (performance, repeat, share)
 * and logged workouts (edit, void). New entries start from Νέα καταχώρηση.
 */
export function JournalFlow() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const vault = useWorkoutVault();
  const logs = useQuery({
    queryKey: TRAINING_LOG_ENTRIES_KEY,
    enabled: Boolean(token),
    queryFn: () => listTrainingLogEntries(token!),
  });
  const { repeat, pendingId, error } = useRepeatWorkout();
  const [performance, setPerformance] = useState<HistoryEntry | null>(null);
  const [sharingId, setSharingId] = useState<string | null>(null);
  const [logDialog, setLogDialog] = useState<TrainingLogDialogState>({ mode: "closed" });
  const days = useMemo(
    () => journalFlow({ executions: historyEntries(vault.data ?? []), logs: logs.data ?? [] }),
    [vault.data, logs.data],
  );
  const failed = vault.isError ? vault : logs.isError ? logs : null;

  return (
    <ClientPage
      title={i18n("workoutHistory4c84737")}
      intro={i18n("clHistoryIntro")}
      actions={
        <Link
          href="/journal/vault"
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--border)", color: "var(--text)" }}
        >
          {i18n("clOpenVault")}
        </Link>
      }
    >
      {error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {clientErrorMessage(error, i18n)}
        </p>
      ) : null}

      {vault.isPending || logs.isPending ? (
        <LoadingLine />
      ) : failed ? (
        <QueryProblem error={failed.error} onRetry={() => void failed.refetch()} />
      ) : days.length === 0 ? (
        <EmptyLine>{i18n("clHistoryEmpty")}</EmptyLine>
      ) : (
        <ol className="flex flex-col gap-5">
          {days.map((day) => (
            <li key={day.day}>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                <time dateTime={day.day}>{formatDay(day.day, locale)}</time>
              </h2>
              <ul className="flex flex-col gap-2">
                {day.items.map((item) =>
                  item.kind === "log" ? (
                    <TrainingLogEntryCard
                      key={item.id}
                      entry={item.entry}
                      locale={locale}
                      onEdit={() => setLogDialog({ mode: "edit", entry: item.entry })}
                      onVoid={() => setLogDialog({ mode: "void", entry: item.entry })}
                    />
                  ) : (
                    <ExecutionRow
                      key={item.id}
                      entry={item.entry}
                      locale={locale}
                      onPerformance={() => setPerformance(item.entry)}
                      onRepeat={() => void repeat(item.entry)}
                      onShare={() => setSharingId(item.entry.id)}
                      repeating={pendingId === item.entry.id}
                      disabled={Boolean(pendingId)}
                    />
                  ),
                )}
              </ul>
            </li>
          ))}
        </ol>
      )}

      {performance ? (
        <ExecutionPerformanceModal
          executionId={performance.id}
          workoutTitle={performance.workout_title}
          onClose={() => setPerformance(null)}
        />
      ) : null}
      {sharingId && token ? <ShareExecution token={token} executionId={sharingId} onClose={() => setSharingId(null)} /> : null}
      {logDialog.mode !== "closed" && token ? (
        <TrainingLogDialog
          state={logDialog}
          token={token}
          onNavigate={setLogDialog}
          onClose={() => setLogDialog({ mode: "closed" })}
        />
      ) : null}
    </ClientPage>
  );
}

function ExecutionRow({
  entry,
  locale,
  onPerformance,
  onRepeat,
  onShare,
  repeating,
  disabled,
}: {
  entry: HistoryEntry;
  locale: string;
  onPerformance: () => void;
  onRepeat: () => void;
  onShare: () => void;
  repeating: boolean;
  disabled: boolean;
}) {
  const i18n = useUiTranslations();
  const title = entry.workout_title ?? i18n("workout39463a5");
  const elapsed = formatElapsed(entry.total_elapsed_ms);
  return (
    <li
      className="flex flex-col gap-3 rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="min-w-0">
        <p className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>
          {title}
        </p>
        <p className="mt-1 flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--dim)" }}>
          <time dateTime={entry.completed_at_utc}>{formatTime(entry.completed_at_utc, locale)}</time>
          {entry.workout_type ? <SemanticLabel value={entry.workout_type} /> : null}
          {elapsed ? <span className="tabular-nums">{i18n("clElapsedValue", { time: elapsed })}</span> : null}
          {entry.scale_level_slug ? <SemanticLabel value={entry.scale_level_slug} /> : null}
          <SourceBadge source={entry.source} />
        </p>
      </div>
      <EntryActions
        workoutTitle={title}
        onPerformance={onPerformance}
        onRepeat={onRepeat}
        onShare={onShare}
        repeating={repeating}
        disabled={disabled}
      />
    </li>
  );
}

/** "Κοινοποίηση στο Milos" of one finished workout, kept from the old landing. */
function ShareExecution({ token, executionId, onClose }: { token: string; executionId: string; onClose: () => void }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const shareExport = useShareExport();
  const execution = useQuery({
    queryKey: ["execution", executionId],
    queryFn: () => fetchExecution(token, executionId),
  });
  if (!execution.data) return null;
  return (
    <InAppShareDialog
      message={renderText(buildExecutionDocument(execution.data, shareExport.labels, locale))}
      onClose={onClose}
      title={execution.data.workout_title ?? i18n("workout39463a5")}
    />
  );
}
