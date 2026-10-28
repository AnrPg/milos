"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { GoalStepper } from "@/components/training-goal/GoalStepper";
import { goalBounds, goalSetterNote, weeklyTarget } from "@/components/training-goal/training-goal";
import { useSetTrainingGoal, useTrainingGoal } from "@/components/training-goal/use-training-goal";

/**
 * Εγώ › Ρυθμίσεις › Πρόγραμμα προπόνησης: my own weekly workout goal
 * (ADR-222). Saved on every step; a goal my coach set says so, and I can
 * still change it.
 */
export function WeeklyGoalSetting() {
  const t = useTranslations("TrainingGoal");
  const goal = useTrainingGoal();
  const save = useSetTrainingGoal();
  const [draft, setDraft] = useState<number | null>(null);
  const value = draft ?? weeklyTarget(goal.data);
  const { min, max } = goalBounds(goal.data);
  // The save writes the query cache, so the note always follows the latest goal.
  // Nothing to say while it loads or failed to load.
  const note = goal.data ? goalSetterNote(goal.data) : null;

  function change(next: number) {
    setDraft(next);
    save.mutate(next, { onSettled: () => setDraft(null) });
  }

  return (
    <div className="space-y-3" data-testid="weekly-goal-setting">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("title")}
      </p>
      <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
        {t("hint")}
      </p>
      {goal.isError && !goal.data ? (
        // Never offer a stepper on a guessed value: a press would overwrite the real goal.
        <ErrorNotice>
          {t("loadFailed")}{" "}
          <button type="button" className="underline" onClick={() => void goal.refetch()}>
            {t("retry")}
          </button>
        </ErrorNotice>
      ) : (
        <GoalStepper value={value} min={min} max={max} disabled={!goal.data || save.isPending} onChange={change} />
      )}
      {note?.kind === "default" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("defaultNote")}</p>
      ) : null}
      {note?.kind === "coach" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("setByCoach", { name: note.name })}</p>
      ) : null}
      {note?.kind === "staff" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("setByStaff", { name: note.name })}</p>
      ) : null}
      {save.isError ? <ErrorNotice>{t("saveFailed")}</ErrorNotice> : null}
    </div>
  );
}
