"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";

import { fetchWorkoutVault } from "@/api/executions";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { EntryActions, SourceBadge } from "@/components/client/EntryActions";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay, formatTime } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { formatElapsed, groupHistoryByDay, historyEntries, type HistoryEntry } from "@/components/client/vault";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

export const WORKOUT_VAULT_QUERY_KEY = ["executions", "vault"] as const;

export function useWorkoutVault() {
  const { tokens } = useSession();
  return useQuery({
    queryKey: WORKOUT_VAULT_QUERY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutVault(tokens!.access_token),
  });
}

/** `/my-workouts/history`: every completed execution by date (ADR-098). */
export function WorkoutHistory() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const vault = useWorkoutVault();
  const { repeat, pendingId, error } = useRepeatWorkout();
  const [performance, setPerformance] = useState<HistoryEntry | null>(null);
  const days = useMemo(() => groupHistoryByDay(historyEntries(vault.data ?? [])), [vault.data]);

  return (
    <ClientPage
      title={i18n("workoutHistory4c84737")}
      intro={i18n("clHistoryIntro")}
      actions={
        <Link
          href="/profile#vault"
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

      {vault.isPending ? (
        <LoadingLine />
      ) : vault.isError ? (
        <QueryProblem error={vault.error} onRetry={() => void vault.refetch()} />
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
                {day.entries.map((entry) => {
                  const title = entry.workout_title ?? i18n("workout39463a5");
                  const elapsed = formatElapsed(entry.total_elapsed_ms);
                  return (
                    <li
                      key={entry.id}
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
                        onPerformance={() => setPerformance(entry)}
                        onRepeat={() => void repeat(entry)}
                        repeating={pendingId === entry.id}
                        disabled={Boolean(pendingId)}
                      />
                    </li>
                  );
                })}
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
    </ClientPage>
  );
}
