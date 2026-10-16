"use client";

import { useEffect, useMemo, useState } from "react";

import { fetchMyTrainingHistory } from "@/api/training-history";
import { TrainingHistory } from "@/components/history/TrainingHistory";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { EntryActions } from "@/components/client/EntryActions";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { useWorkoutVault } from "@/components/client/use-workout-vault";
import {
  formatElapsed,
  groupFinishedWorkouts,
  historyEntries,
  type FinishedWorkout,
  type FinishedWorkoutFolder,
  type HistoryEntry,
} from "@/components/client/vault";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { defaultHistoryKind } from "@/lib/training-history";

type ViewMode = "folders" | "tree";

const VIEW_KEY = "milos.journal.view";

function storedView(): ViewMode {
  try {
    return window.localStorage.getItem(VIEW_KEY) === "tree" ? "tree" : "folders";
  } catch {
    return "folders";
  }
}

/** `/journal`: every finished workout, in folders or as a tree (ADR-103). */
export function JournalWorkouts() {
  const i18n = useUiTranslations();
  const vault = useWorkoutVault();
  const { tokens, currentUser } = useSession();
  const { repeat, pendingId, error } = useRepeatWorkout();
  const [view, setViewState] = useState<ViewMode>("folders");
  const [openFolder, setOpenFolder] = useState<string | null>(null);
  const [performance, setPerformance] = useState<HistoryEntry | null>(null);
  const folders = useMemo(() => groupFinishedWorkouts(historyEntries(vault.data ?? [])), [vault.data]);

  useEffect(() => {
    queueMicrotask(() => setViewState(storedView()));
  }, []);

  const setView = (next: ViewMode) => {
    setViewState(next);
    try {
      window.localStorage.setItem(VIEW_KEY, next);
    } catch {}
  };

  const folderKey = (folder: FinishedWorkoutFolder) => folder.type ?? "";
  const current = openFolder === null ? null : folders.find((folder) => folderKey(folder) === openFolder) ?? null;
  const actions = {
    onPerformance: setPerformance,
    onRepeat: (entry: HistoryEntry) => void repeat(entry),
    pendingId,
  };

  return (
    <ClientPage
      title={i18n("jrnWorkoutsTitle")}
      intro={i18n("jrnWorkoutsIntro")}
      actions={
        <div className="flex items-center gap-1" role="group" aria-label={i18n("jrnViewLabel")}>
          {(["folders", "tree"] as const).map((mode) => (
            <button
              key={mode}
              type="button"
              aria-pressed={view === mode}
              title={mode === "folders" ? i18n("jrnViewFolders") : i18n("jrnViewTree")}
              aria-label={mode === "folders" ? i18n("jrnViewFolders") : i18n("jrnViewTree")}
              className="grid h-9 w-9 place-items-center rounded-full text-sm"
              style={{
                background: view === mode ? "var(--text)" : "var(--panel)",
                color: view === mode ? "var(--bg)" : "var(--text-soft)",
                border: "1px solid var(--border)",
              }}
              onClick={() => setView(mode)}
            >
              {mode === "folders" ? "📁" : "☰"}
            </button>
          ))}
        </div>
      }
    >
      {error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {clientErrorMessage(error, i18n)}
        </p>
      ) : null}

      {vault.isPending ? (
        <LoadingLine />
      ) : vault.isError ? (
        <QueryProblem error={vault.error} onRetry={() => void vault.refetch()} />
      ) : folders.length === 0 ? (
        <EmptyLine>{i18n("clHistoryEmpty")}</EmptyLine>
      ) : view === "tree" ? (
        <ul className="flex flex-col gap-2">
          {folders.map((folder) => (
            <li key={folderKey(folder)}>
              <details open className="rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <summary className="cursor-pointer list-none px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
                  📁 <FolderName folder={folder} /> <Count value={folder.workouts.length} />
                </summary>
                <ul className="flex flex-col gap-1 px-3 pb-3">
                  {folder.workouts.map((workout) => (
                    <li key={workout.master_workout_id}>
                      <details className="rounded-xl" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                        <summary className="cursor-pointer list-none px-3 py-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {workout.title ?? i18n("workout39463a5")} <Count value={workout.entries.length} />
                        </summary>
                        <EntryList workout={workout} {...actions} />
                      </details>
                    </li>
                  ))}
                </ul>
              </details>
            </li>
          ))}
        </ul>
      ) : current ? (
        <div className="flex flex-col gap-4">
          <nav className="flex items-center gap-2 text-sm" aria-label={i18n("jrnViewFolders")}>
            <button
              type="button"
              className="rounded-full px-3 py-1.5 font-semibold"
              style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
              onClick={() => setOpenFolder(null)}
            >
              {i18n("jrnAllFolders")}
            </button>
            <span aria-hidden="true" className="rtl:rotate-180" style={{ color: "var(--dim)" }}>›</span>
            <span className="rounded-full px-3 py-1.5 font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }}>
              <FolderName folder={current} />
            </span>
          </nav>
          <div className="grid gap-4 lg:grid-cols-2">
            {current.workouts.map((workout) => (
              <article key={workout.master_workout_id} className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <h2 className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>
                  {workout.title ?? i18n("workout39463a5")}
                </h2>
                <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                  {i18n("jrnTimesDone", { count: workout.entries.length })}
                </p>
                <EntryList workout={workout} {...actions} />
              </article>
            ))}
          </div>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {folders.map((folder) => (
            <button
              key={folderKey(folder)}
              type="button"
              className="flex items-center gap-3 rounded-2xl p-4 text-start transition-opacity hover:opacity-85"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              onClick={() => setOpenFolder(folderKey(folder))}
            >
              <span aria-hidden="true" className="text-2xl">📁</span>
              <span className="min-w-0">
                <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>
                  <FolderName folder={folder} />
                </span>
                <span className="block text-xs" style={{ color: "var(--dim)" }}>
                  {i18n("jrnWorkoutCount", { count: folder.workouts.length })}
                </span>
              </span>
            </button>
          ))}
        </div>
      )}

      {tokens?.access_token && currentUser ? (
        <TrainingHistory
          id="history"
          queryKey={["me", currentUser.id]}
          fetchPage={(kind, offset) => fetchMyTrainingHistory(tokens.access_token, kind, offset)}
          defaultKind={defaultHistoryKind(currentUser.role)}
        />
      ) : null}

      {performance ? (
        <ExecutionPerformanceModal
          executionId={performance.id}
          workoutTitle={performance.workout_title}
          onClose={() => setPerformance(null)}
        />
      ) : null}
    </ClientPage>
  );
}

function FolderName({ folder }: { folder: FinishedWorkoutFolder }) {
  const i18n = useUiTranslations();
  return folder.type ? <SemanticLabel value={folder.type} /> : <>{i18n("jrnOtherWorkouts")}</>;
}

function Count({ value }: { value: number }) {
  return (
    <span className="ms-1 rounded-full px-2 text-xs tabular-nums" style={{ background: "var(--border)", color: "var(--text-soft)" }}>
      {value}
    </span>
  );
}

function EntryList({
  workout,
  onPerformance,
  onRepeat,
  pendingId,
}: {
  workout: FinishedWorkout;
  onPerformance: (entry: HistoryEntry) => void;
  onRepeat: (entry: HistoryEntry) => void;
  pendingId: string | null;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const title = workout.title ?? i18n("workout39463a5");
  return (
    <ul className="mt-3 flex flex-col gap-2 px-3 pb-3 lg:px-0 lg:pb-0">
      {workout.entries.map((entry) => {
        const elapsed = formatElapsed(entry.total_elapsed_ms);
        return (
          <li key={entry.id} className="flex flex-wrap items-center justify-between gap-2 border-t pt-2 text-sm" style={{ borderColor: "var(--border)" }}>
            <span style={{ color: "var(--text-soft)" }}>
              <time dateTime={entry.completed_at_utc}>{formatDay(entry.day, locale)}</time>
              {elapsed ? <span className="ms-2 tabular-nums" style={{ color: "var(--dim)" }}>{elapsed}</span> : null}
            </span>
            <EntryActions
              workoutTitle={title}
              onPerformance={() => onPerformance(entry)}
              onRepeat={() => onRepeat(entry)}
              repeating={pendingId === entry.id}
              disabled={Boolean(pendingId)}
            />
          </li>
        );
      })}
    </ul>
  );
}
