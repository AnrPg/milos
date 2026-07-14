"use client";

import type { TimerSegment } from "@/api/executions";
import { buildStepId } from "./progress";

export type ChecklistStep = {
  stepId: string;
  stepLabel: string | null;
  exerciseId: string;
  exercise: TimerSegment["exercises"][number];
};

type Props = {
  segment: TimerSegment;
  checkedExerciseIds: string[];
  onToggle: (stepId: string, segmentSteps: ChecklistStep[]) => void;
  onModify: (step: ChecklistStep) => void;
};

export function buildChecklistSteps(segment: TimerSegment): ChecklistStep[] {
  return segment.exercises
    .filter((exercise) => !exercise.excluded)
    .flatMap((exercise) => {
      const setCount = exercise.sets && exercise.sets > 1 ? exercise.sets : 1;

      return Array.from({ length: setCount }, (_, index) => ({
        stepId: buildStepId(segment, exercise, setCount, index + 1),
        stepLabel: setCount > 1 ? `Set ${index + 1}/${setCount}` : null,
        exerciseId: exercise.id,
        exercise,
      }));
    });
}

export function WorkoutChecklist({ segment, checkedExerciseIds, onToggle, onModify }: Props) {
  const steps = buildChecklistSteps(segment);

  if (steps.length === 0) {
    return (
      <div className="py-6 text-center text-sm" style={{ color: "var(--muted)" }}>
        Rest
      </div>
    );
  }

  const doneCount = steps.filter(
    (s) => checkedExerciseIds.includes(s.stepId) || checkedExerciseIds.includes(s.exerciseId),
  ).length;

  const currentStep = steps.find(
    (s) => !checkedExerciseIds.includes(s.stepId) && !checkedExerciseIds.includes(s.exerciseId),
  ) ?? null;

  const { exercise } = currentStep ?? steps[steps.length - 1]!;

  const prescriptionLabel = exercise.prescription_value
    ? `${exercise.prescription_value} ${exercise.prescription_unit ?? ""}`.trim()
    : null;

  const loadLabel = exercise.load_value
    ? exercise.load_mode === "pct_1rm"
      ? `${exercise.load_value}% RM`
      : `${exercise.load_value} kg`
    : exercise.load_mode === "bw"
      ? "BW"
      : null;

  const allDone = doneCount === steps.length;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xs" style={{ color: "var(--dim)" }}>
        <span>
          Step {Math.min(doneCount + 1, steps.length)} of {steps.length}
        </span>
        <span>{doneCount}/{steps.length} done</span>
      </div>

      {allDone ? (
        <div
          className="rounded-2xl px-5 py-6 text-center"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <div className="text-3xl mb-2">✓</div>
          <p className="text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>
            All steps done
          </p>
        </div>
      ) : (
        <div
          className="rounded-2xl p-5 cursor-pointer select-none active:scale-[0.98] transition-transform"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          onClick={() => currentStep && onToggle(currentStep.stepId, steps)}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              currentStep && onToggle(currentStep.stepId, steps);
            }
          }}
        >
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-lg font-bold leading-snug" style={{ color: "var(--text)" }}>
                {exercise.name}
              </p>
              {currentStep?.stepLabel && (
                <p className="mt-0.5 text-sm font-semibold" style={{ color: "var(--primary)" }}>
                  {currentStep.stepLabel}
                </p>
              )}
              {(prescriptionLabel ?? loadLabel) && (
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  {prescriptionLabel && (
                    <span
                      className="rounded-full px-3 py-1 text-sm font-semibold"
                      style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
                    >
                      {prescriptionLabel}
                    </span>
                  )}
                  {loadLabel && (
                    <span
                      className="rounded-full px-3 py-1 text-sm font-semibold"
                      style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
                    >
                      {loadLabel}
                    </span>
                  )}
                </div>
              )}
            </div>

            <button
              type="button"
              className="shrink-0 rounded-xl px-3 py-1.5 text-xs font-semibold"
              style={{
                background: "color-mix(in srgb, var(--warning) 14%, transparent)",
                color: "var(--warning)",
                border: "1px solid color-mix(in srgb, var(--warning) 28%, transparent)",
              }}
              onClick={(e) => {
                e.stopPropagation();
                currentStep && onModify(currentStep);
              }}
            >
              Modify
            </button>
          </div>

          <div className="mt-4 pt-4" style={{ borderTop: "1px solid var(--border)" }}>
            <p className="text-xs text-center" style={{ color: "var(--dim)" }}>
              Tap anywhere to mark as done
            </p>
          </div>
        </div>
      )}

      {doneCount > 0 && (
        <div className="flex flex-col gap-1.5">
          {steps
            .filter(
              (s) =>
                checkedExerciseIds.includes(s.stepId) || checkedExerciseIds.includes(s.exerciseId),
            )
            .map((s) => (
              <div
                key={s.stepId}
                className="flex items-center gap-3 rounded-xl px-4 py-2.5 opacity-50"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span
                  className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full text-[10px]"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
                >
                  ✓
                </span>
                <span className="text-sm line-through" style={{ color: "var(--muted)" }}>
                  {s.exercise.name}
                  {s.stepLabel ? ` · ${s.stepLabel}` : ""}
                </span>
              </div>
            ))}
        </div>
      )}
    </div>
  );
}
