"use client";

import { useId, useMemo, useState } from "react";

import type { VaultWorkout } from "@/api/executions";
import { SemanticLabel } from "@/components/semantic-label";
import { EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { EntryActions, SourceBadge } from "@/components/client/EntryActions";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay, formatTime } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { entryDay, filterVault, formatElapsed } from "@/components/client/vault";
import { useWorkoutVault } from "@/components/client/WorkoutHistory";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/** Profile Vault tab: a shelf of every workout the client completed (ADR-098). */
export function WorkoutVault() {
  const i18n = useUiTranslations();
  const vault = useWorkoutVault();
  const searchId = useId();
  const [search, setSearch] = useState("");
  const [openId, setOpenId] = useState<string | null>(null);
  const [performance, setPerformance] = useState<{ id: string; title: string | null } | null>(null);
  const { repeat, pendingId, error } = useRepeatWorkout();
  const workouts = useMemo(() => filterVault(vault.data ?? [], search), [vault.data, search]);

  return (
    <section
      id="vault"
      aria-labelledby={`${searchId}-title`}
      className="rounded-[2.4rem] p-5 sm:p-8"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <h2
        id={`${searchId}-title`}
        className="text-sm font-semibold uppercase tracking-[0.24em]"
        style={{ color: "var(--primary)" }}
      >
        {i18n("clVaultTitle")}
      </h2>
      <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
        {i18n("clVaultIntro")}
      </p>

      {(vault.data?.length ?? 0) > 3 ? (
        <div className="mt-4">
          <label htmlFor={searchId} className="sr-only">
            {i18n("clVaultSearch")}
          </label>
          <input
            id={searchId}
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder={i18n("clVaultSearch")}
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </div>
      ) : null}

      {error ? (
        <p role="alert" className="mt-3 text-sm" style={{ color: "var(--danger)" }}>
          {clientErrorMessage(error, i18n)}
        </p>
      ) : null}

      <div className="mt-4">
        {vault.isPending ? (
          <LoadingLine />
        ) : vault.isError ? (
          <QueryProblem error={vault.error} onRetry={() => void vault.refetch()} />
        ) : (vault.data ?? []).length === 0 ? (
          <EmptyLine>{i18n("clVaultEmpty")}</EmptyLine>
        ) : workouts.length === 0 ? (
          <EmptyLine>{i18n("clVaultNoMatch")}</EmptyLine>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2">
            {workouts.map((workout) => (
              <VaultCard
                key={workout.master_workout_id}
                workout={workout}
                open={openId === workout.master_workout_id}
                onToggle={() =>
                  setOpenId((current) => (current === workout.master_workout_id ? null : workout.master_workout_id))
                }
                onPerformance={(id) => setPerformance({ id, title: workout.workout_title ?? null })}
                onRepeat={(entry) => void repeat({ ...entry, master_workout_id: workout.master_workout_id })}
                pendingId={pendingId}
              />
            ))}
          </ul>
        )}
      </div>

      {performance ? (
        <ExecutionPerformanceModal
          executionId={performance.id}
          workoutTitle={performance.title}
          onClose={() => setPerformance(null)}
        />
      ) : null}
    </section>
  );
}

function VaultCard({
  workout,
  open,
  onToggle,
  onPerformance,
  onRepeat,
  pendingId,
}: {
  workout: VaultWorkout;
  open: boolean;
  onToggle: () => void;
  onPerformance: (executionId: string) => void;
  onRepeat: (entry: VaultWorkout["entries"][number]) => void;
  pendingId: string | null;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const entriesId = useId();
  const title = workout.workout_title ?? i18n("workout39463a5");
  const lastDay = entryDay(workout.last_completed_at, workout.entries[0]?.completed_at_tz);

  return (
    <li
      className={(open ? "sm:col-span-2 " : "") + "rounded-2xl"}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        aria-controls={entriesId}
        className="flex w-full items-start justify-between gap-3 p-4 text-start"
      >
        <span className="min-w-0">
          <span className="block break-words text-base font-semibold" style={{ color: "var(--text)" }}>
            {title}
          </span>
          <span className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs" style={{ color: "var(--dim)" }}>
            {workout.workout_type ? <SemanticLabel value={workout.workout_type} /> : null}
            <span>{i18n("clVaultCount", { count: workout.completed_count })}</span>
            <span>{i18n("clVaultLast", { date: formatDay(lastDay, locale, { weekday: undefined, month: "short" }) })}</span>
          </span>
        </span>
        <span aria-hidden="true" className="text-xl font-light" style={{ color: "var(--dim)" }}>
          {open ? "−" : "+"}
        </span>
      </button>
      {open ? (
        <ul id={entriesId} className="flex flex-col gap-2 border-t px-4 py-3" style={{ borderColor: "var(--border)" }}>
          {workout.entries.map((entry) => {
            const day = entryDay(entry.completed_at_utc, entry.completed_at_tz);
            const elapsed = formatElapsed(entry.total_elapsed_ms);
            return (
              <li key={entry.id} className="flex flex-col gap-2 py-1 sm:flex-row sm:items-center sm:justify-between">
                <p className="flex flex-wrap items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
                  <time dateTime={entry.completed_at_utc} className="font-semibold" style={{ color: "var(--text)" }}>
                    {formatDay(day, locale, { weekday: "short", month: "short" })}
                  </time>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {formatTime(entry.completed_at_utc, locale)}
                  </span>
                  {elapsed ? (
                    <span className="text-xs tabular-nums" style={{ color: "var(--dim)" }}>
                      {i18n("clElapsedValue", { time: elapsed })}
                    </span>
                  ) : null}
                  <SourceBadge source={entry.source} />
                </p>
                <EntryActions
                  workoutTitle={title}
                  onPerformance={() => onPerformance(entry.id)}
                  onRepeat={() => onRepeat(entry)}
                  repeating={pendingId === entry.id}
                  disabled={Boolean(pendingId)}
                />
              </li>
            );
          })}
        </ul>
      ) : null}
    </li>
  );
}
