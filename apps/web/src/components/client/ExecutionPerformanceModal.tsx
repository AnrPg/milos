"use client";

import { useId } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchExecution } from "@/api/executions";
import { CommentList } from "@/components/journal/CommentList";
import { exerciseNamesOf } from "@/lib/journal-comments";
import { LocalizedScore } from "@/components/localized-score";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { clientErrorMessage } from "@/components/client/errors";
import { formatDateTime } from "@/components/client/format";
import { formatElapsed } from "@/components/client/vault";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/** That day's result of one execution: time, section scores, changes and notes. */
export function ExecutionPerformanceModal({
  executionId,
  workoutTitle,
  onClose,
}: {
  executionId: string;
  workoutTitle?: string | null;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const ref = useModalFocusTrap<HTMLDivElement>(onClose);
  const titleId = useId();
  const query = useQuery({
    queryKey: ["execution", executionId],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchExecution(tokens!.access_token, executionId),
  });
  const execution = query.data;
  const exerciseNames = exerciseNamesOf(execution?.workout);
  const elapsed = formatElapsed(execution?.total_elapsed_ms);
  const tile = "rounded-2xl px-4 py-3";
  const tileStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)" };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-3 sm:items-center sm:p-4"
      style={{ background: "rgba(0,0,0,0.65)" }}
      onClick={onClose}
      role="presentation"
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="max-h-[88vh] w-full max-w-2xl overflow-y-auto rounded-[2rem] p-5 outline-none sm:p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
              {i18n("clSeePerformance")}
            </p>
            <h2 id={titleId} className="mt-2 break-words text-xl font-semibold" style={{ color: "var(--text)" }}>
              {execution?.workout_title ?? workoutTitle ?? i18n("workout39463a5")}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("closebbfa773")}
          </button>
        </div>

        {query.isPending ? (
          <p className="mt-6 text-sm" role="status" style={{ color: "var(--dim)" }}>
            {i18n("loadingExecutionDetailscda7566")}
          </p>
        ) : query.isError || !execution ? (
          <p className="mt-6 text-sm" role="alert" style={{ color: "var(--danger)" }}>
            {query.error ? clientErrorMessage(query.error, i18n) : i18n("executionDetailsCouldNotBeLoaded30a9f0a")}
          </p>
        ) : (
          <div className="mt-5 space-y-5">
            <div className="grid gap-3 sm:grid-cols-3">
              <div className={tile} style={tileStyle}>
                <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("completed1798b3b")}</p>
                <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {formatDateTime(execution.completed_at_utc, locale) || i18n("inProgressb6bd42e")}
                </p>
              </div>
              <div className={tile} style={tileStyle}>
                <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("clElapsedTime")}</p>
                <p className="mt-1 text-sm font-semibold tabular-nums" style={{ color: "var(--text)" }}>
                  <bdi>{elapsed ?? "—"}</bdi>
                </p>
              </div>
              <div className={tile} style={tileStyle}>
                <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("scalea29f025")}</p>
                <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                  <SemanticLabel value={execution.scale_level_slug ?? "base"} />
                </p>
              </div>
            </div>

            <div>
              <h3 className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                {i18n("sectionScorescaef89a")}
              </h3>
              <ul className="mt-2 space-y-2">
                {execution.section_scores.length === 0 ? (
                  <li className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                    {i18n("noScoresWereSubmitted1a2f165")}
                  </li>
                ) : (
                  execution.section_scores.map((score) => {
                    const sectionTime = formatElapsed(execution.section_elapsed_ms?.[score.section_id]);
                    return (
                      <li
                        key={score.section_id}
                        className="flex flex-wrap items-baseline justify-between gap-2 rounded-2xl px-4 py-3 text-sm"
                        style={tileStyle}
                      >
                        <span className="font-semibold" style={{ color: "var(--text)" }}>
                          {score.section_name ?? score.section_id}
                        </span>
                        <span style={{ color: "var(--text-soft)" }}>
                          <LocalizedScore value={score.value} scoreType={score.score_type} unit={score.unit} />
                          {sectionTime ? (
                            <span className="ms-2 text-xs tabular-nums" style={{ color: "var(--dim)" }}>
                              <bdi>{sectionTime}</bdi>
                            </span>
                          ) : null}
                        </span>
                      </li>
                    );
                  })
                )}
              </ul>
            </div>

            <div>
              <h3 className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                {i18n("modificationsAndNotes8a73e2c")}
              </h3>
              <div className="mt-2">
                <CommentList
                  comments={execution.comments ?? []}
                  anchorLabel={(comment) => (comment.exercise_id ? (exerciseNames[comment.exercise_id] ?? null) : null)}
                  emptyText={i18n("noExerciseNotesWereSubmittedb9552b2")}
                />
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
