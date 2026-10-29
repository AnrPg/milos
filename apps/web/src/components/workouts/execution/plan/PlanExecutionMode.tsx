"use client";

/**
 * ADR-270: running a workout written in the structured editor
 * (`authoring_mode = structured_plan`). Loads the execution and its workout,
 * runs each plan section in turn with `PlanExecution`, saves what the
 * athlete logged as Σχόλια changes (ADR-140 §1) and finishes in the shared
 * `FinishWizard`.
 */
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import React, { useEffect, useMemo, useRef, useState } from "react";

import { completeExecution, fetchExecution, type PlanSetActual, type SectionScore } from "@/api/executions";
import type { JournalComment } from "@/api/journal-comments";
import { listPRs } from "@/api/gamification";
import { fetchWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { BackButton } from "@/components/ui/BackLink";
import { useJournalCommentWriter } from "@/hooks/useJournalCommentWriter";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { changeDraft, finishWrites, type FinishComments } from "@/lib/journal-comments";

import { FinishWizard } from "../FinishWizard";
import { PlanExecution, type PlanRunLog, type PlanRunResult, type PlanRunSnapshot } from "./PlanExecution";
import { decimal, type OneRepMaxLookup } from "./actuals";
import { oneRepMaxLookup } from "./one-rep-max";
import { readPlanProgress, storePlanProgress } from "./plan-progress";
import { planSections, type RunnablePlanSection } from "./plan-workout";
import { scoreSegment } from "./score";

type Loaded = { title: string; sections: RunnablePlanSection[] };

/** A logged or prescribed value: a decimal number when it reads as one ("22,5", "65 kg"), else the text. */
const asValue = (text: string): string | number => decimal(text) ?? text;

export function PlanExecutionMode({ executionId }: { executionId: string }) {
  const t = useTranslations("PlanRun");
  const router = useRouter();
  const { tokens } = useSession();
  const commentWriter = useJournalCommentWriter();
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [failed, setFailed] = useState(false);
  // A reload resumes where the athlete was (this device only).
  const [restored] = useState(() => readPlanProgress(executionId));
  const [index, setIndex] = useState(restored?.index ?? 0);
  const [scores, setScores] = useState<SectionScore[]>(restored?.scores ?? []);
  const [elapsed, setElapsed] = useState<Record<string, number>>(restored?.elapsed ?? {});
  const [actuals, setActuals] = useState<Record<string, PlanSetActual[]>>(restored?.actuals ?? {});
  const [comments, setComments] = useState<JournalComment[]>([]);
  const [finishing, setFinishing] = useState(restored?.finishing ?? false);
  const [oneRepMax, setOneRepMax] = useState<OneRepMaxLookup | undefined>(undefined);
  const currentRef = useRef<{ index: number; snapshot: PlanRunSnapshot | null }>({
    index: restored?.index ?? 0,
    snapshot: restored?.current ?? null,
  });
  const [initialSnapshot] = useState(() => restored?.current ?? null);
  const baseRef = useRef({ index, scores, elapsed, actuals, finishing });
  useEffect(() => {
    baseRef.current = { index, scores, elapsed, actuals, finishing };
    if (currentRef.current.index !== index) currentRef.current = { index, snapshot: null };
    storePlanProgress(executionId, { ...baseRef.current, current: currentRef.current.snapshot });
  }, [actuals, elapsed, executionId, finishing, index, scores]);

  function saveSnapshot(sectionIndex: number, snapshot: PlanRunSnapshot) {
    if (sectionIndex !== baseRef.current.index) return;
    currentRef.current = { index: sectionIndex, snapshot };
    storePlanProgress(executionId, { ...baseRef.current, current: snapshot });
  }
  const [saving, setSaving] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);
  const accessToken = tokens?.access_token ?? null;

  useScreenWakeLock(Boolean(loaded) && !finishing);

  useEffect(() => {
    if (!accessToken) return;
    let cancelled = false;
    (async () => {
      try {
        const execution = await fetchExecution(accessToken, executionId);
        const workout = execution.master_workout_id ? await fetchWorkout(accessToken, execution.master_workout_id) : null;
        if (cancelled) return;
        if (!workout) {
          setFailed(true);
          return;
        }
        setLoaded({ title: workout.title, sections: planSections(workout) });
        setComments(execution.comments ?? []);
        // The athlete's 1RMs (their PRs) turn % loads into kg; without them % stays %.
        listPRs(accessToken)
          .then((prs) => {
            // Built here, not in the state updater, so a bad answer can never throw during render.
            const lookup = oneRepMaxLookup(prs);
            if (!cancelled) setOneRepMax(() => lookup);
          })
          .catch(() => undefined);
      } catch {
        if (!cancelled) setFailed(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [accessToken, executionId]);

  const segments = useMemo(
    () =>
      (loaded?.sections ?? []).flatMap((s) => {
        const segment = scoreSegment(s.id, s.name, s.plan.score, s.plan.score ? t(`score.${s.plan.score}`) : "");
        return segment ? [segment] : [];
      }),
    [loaded?.sections, t],
  );

  async function log(section: RunnablePlanSection, entry: PlanRunLog) {
    const { step, field, actual, canonical } = entry;
    const draft = changeDraft("execution", executionId, {
      patch_id: ["plan", section.id, step.rowId, step.block, step.round, step.part?.index ?? 0, entry.occurrence, field].join(":"),
      field: field === "reps" ? "reps" : "load",
      type: field === "reps" ? "reps_changed" : "weight_changed",
      section_id: section.id,
      section_name: section.name,
      exercise_id: step.rowId,
      exercise_name: step.name,
      set_index: step.round,
      round_index: step.interrupt ? entry.occurrence : step.round,
      actual_value: asValue(actual),
      canonical_value: asValue(canonical),
      ...(field === "load" ? { unit: "kg" } : {}),
    });
    try {
      const { comment } = await commentWriter.save(draft);
      setComments((current) => [...current.filter((c) => c.id !== comment.id && c.change?.patch_id !== comment.change?.patch_id), comment]);
    } catch {
      setFeedback(t("saveFailed"));
    }
  }

  function completeSection(section: RunnablePlanSection, result: PlanRunResult) {
    if (result.score) setScores((current) => [...current.filter((s) => s.section_id !== section.id), result.score!]);
    setElapsed((current) => ({ ...current, [section.id]: result.elapsedMs }));
    setActuals((current) => ({ ...current, [section.id]: result.actuals }));
    if (loaded && index + 1 < loaded.sections.length) setIndex(index + 1);
    else setFinishing(true);
  }

  async function confirmFinish(edited: SectionScore[], finish: FinishComments) {
    if (!accessToken) return;
    setSaving(true);
    setFeedback(null);
    try {
      const writes = finishWrites("execution", executionId, comments, finish);
      for (const draft of writes.save) await commentWriter.save(draft);
      for (const id of writes.remove) await commentWriter.remove(id);
      await completeExecution(accessToken, executionId, {
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        checked_exercise_ids: [],
        section_scores: edited,
        total_elapsed_ms: Math.round(Object.values(elapsed).reduce((a, b) => a + b, 0)),
        section_elapsed_ms: elapsed,
        segment_cycle_counts: {},
        plan_actuals: (loaded?.sections ?? []).flatMap((s) => actuals[s.id] ?? []),
      });
      storePlanProgress(executionId, null);
      router.push("/");
    } catch {
      setFeedback(t("saveFailed"));
    } finally {
      setSaving(false);
    }
  }

  if (failed || (loaded && loaded.sections.length === 0)) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center gap-4 px-6 text-center text-sm" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        <p>{t("nothing")}</p>
        <BackButton type="button" onClick={() => router.push("/workouts")} className="rounded-xl px-4 py-2" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t("back")}
        </BackButton>
      </div>
    );
  }

  if (!loaded) {
    return (
      <div className="flex min-h-dvh items-center justify-center px-6 text-sm" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {t("loading")}
      </div>
    );
  }

  if (finishing) {
    return (
      <FinishWizard
        scores={scores}
        segments={segments}
        comments={comments}
        feltExecutionId={executionId}
        isSaving={saving}
        feedback={feedback}
        onConfirm={confirmFinish}
        onCancel={() => setFinishing(false)}
      />
    );
  }

  const section = loaded.sections[Math.min(index, loaded.sections.length - 1)];
  return (
    <div className="flex min-h-dvh flex-col" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <header className="flex items-center justify-between gap-3 border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
        <BackButton type="button" onClick={() => router.back()} className="rounded-xl px-3 py-2 text-sm" style={{ color: "var(--muted)" }}>
          {t("back")}
        </BackButton>
        <div className="min-w-0 text-center">
          <div className="truncate text-sm font-bold">{loaded.title}</div>
          {loaded.sections.length > 1 ? (
            <div className="text-xs" style={{ color: "var(--dim)" }}>
              {t("sectionOf", { n: index + 1, total: loaded.sections.length })}
            </div>
          ) : null}
        </div>
        <span className="w-12" aria-hidden="true" />
      </header>
      {feedback ? (
        <p role="alert" className="px-4 pt-2 text-sm" style={{ color: "var(--danger)" }}>
          {feedback}
        </p>
      ) : null}
      <main className="mx-auto flex w-full max-w-xl flex-1 flex-col">
        <PlanExecution
          key={section.id}
          section={section.plan}
          sectionId={section.id}
          sectionName={section.name}
          existingScore={scores.find((s) => s.section_id === section.id)}
          onComplete={(result) => completeSection(section, result)}
          onLog={(entry) => void log(section, entry)}
          oneRepMaxKg={oneRepMax}
          initial={index === (restored?.index ?? 0) ? initialSnapshot : null}
          onProgress={(snapshot) => saveSnapshot(index, snapshot)}
        />
      </main>
    </div>
  );
}
