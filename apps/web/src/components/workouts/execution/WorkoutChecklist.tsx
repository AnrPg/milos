"use client";

import { useUiTranslations } from "@/i18n/ui";
import { semanticLabel } from "@/i18n/presentation";
import type { TimerSegment } from "@/api/executions";
import { buildSegmentStepDefinitions, type SegmentStepDefinition } from "./progress";

export type ChecklistStep = {
  stepId: string;
  stepLabel: string | null;
  exerciseId: string;
  exercise: TimerSegment["exercises"][number];
  setNumber: number;
  setPrescription: SegmentStepDefinition["setPrescription"];
  groupKind: "superset" | "alternating" | null;
  groupId: string | null;
};

type Props = {
  steps: ChecklistStep[];
  sectionNote?: string | null;
  checkedExerciseIds: string[];
  /** Overrides each step's prescribed reps (Death By grows them every window). */
  targetReps?: number | null;
  onToggle: (stepId: string) => void;
  onModify: (step: ChecklistStep) => void;
};

export function toChecklistSteps(definitions: SegmentStepDefinition[]): ChecklistStep[] {
  return definitions.map((step) => ({
    stepId: step.stepId,
    stepLabel: step.setCount > 1 ? `${step.setNumber}/${step.setCount}` : null,
    exerciseId: step.exercise.id,
    exercise: step.exercise,
    setNumber: step.setNumber,
    setPrescription: step.setPrescription,
    groupKind: step.groupKind,
    groupId: step.groupId,
  }));
}

export function buildChecklistSteps(segment: TimerSegment): ChecklistStep[] {
  return toChecklistSteps(buildSegmentStepDefinitions(segment));
}

export function isStepChecked(step: ChecklistStep, checkedExerciseIds: string[]) {
  return checkedExerciseIds.includes(step.stepId) || checkedExerciseIds.includes(step.exerciseId);
}

function usePrescription(step: ChecklistStep, targetReps: number | null | undefined) {
  const i18n = useUiTranslations();
  const { exercise } = step;
  const prescriptionValue = targetReps ?? step.setPrescription?.prescription_value ?? exercise.prescription_value;
  const prescriptionUnit = targetReps ? "reps" : step.setPrescription?.prescription_unit ?? exercise.prescription_unit;
  const loadValue = step.setPrescription?.load_value ?? exercise.load_value;
  const loadMode = step.setPrescription?.load_mode ?? exercise.load_mode;

  const prescription = prescriptionValue
    ? `${prescriptionValue} ${semanticLabel(prescriptionUnit ?? "reps", i18n)}`
    : null;

  const load = loadValue
    ? loadMode === "pct_1rm"
      ? `${loadValue}${i18n("rma904756")}`
      : `${loadValue} ${semanticLabel("kg", i18n)}`
    : loadMode === "bw"
      ? i18n("bw4d64743")
      : null;

  return { prescription, load };
}

export function WorkoutChecklist({
  steps,
  sectionNote,
  checkedExerciseIds,
  targetReps,
  onToggle,
  onModify,
}: Props) {
  const i18n = useUiTranslations();

  if (steps.length === 0) {
    return (
      <div className="py-6 text-center text-sm" style={{ color: "var(--muted)" }}>
        {i18n("restb79e5f4")}
      </div>
    );
  }

  const currentStep = steps.find((step) => !isStepChecked(step, checkedExerciseIds)) ?? null;
  const doneCount = steps.filter((step) => isStepChecked(step, checkedExerciseIds)).length;

  return (
    <div className="flex flex-col gap-3">
      {sectionNote ? (
        <div className="text-xs italic" style={{ color: "var(--muted)" }}>
          {sectionNote}
        </div>
      ) : null}

      {currentStep ? (
        <CurrentStepCard
          step={currentStep}
          targetReps={targetReps}
          onDone={() => onToggle(currentStep.stepId)}
          onModify={() => onModify(currentStep)}
        />
      ) : (
        <div
          className="rounded-2xl px-5 py-5 text-center"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <div className="mb-1 text-3xl" aria-hidden="true">✓</div>
          <p className="text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>
            {i18n("allStepsDone226c28e")}
          </p>
        </div>
      )}

      <div className="flex items-center justify-between text-xs" style={{ color: "var(--dim)" }}>
        <span>{doneCount}/{steps.length} {i18n("donee5fd9cf")}</span>
      </div>

      <ul className="flex flex-col gap-1.5">
        {steps.map((step) => (
          <StepRow
            key={step.stepId}
            step={step}
            checked={isStepChecked(step, checkedExerciseIds)}
            current={step.stepId === currentStep?.stepId}
            targetReps={targetReps}
            onToggle={() => onToggle(step.stepId)}
          />
        ))}
      </ul>
    </div>
  );
}

function CurrentStepCard({
  step,
  targetReps,
  onDone,
  onModify,
}: {
  step: ChecklistStep;
  targetReps?: number | null;
  onDone: () => void;
  onModify: () => void;
}) {
  const i18n = useUiTranslations();
  const { prescription, load } = usePrescription(step, targetReps);
  const groupColor = step.groupKind === "superset" ? "var(--primary)" : "var(--info)";

  return (
    <div
      className="rounded-2xl p-4"
      style={{
        background: "var(--panel)",
        border: `1px solid ${step.groupKind ? groupColor : "var(--border)"}`,
        boxShadow: step.groupKind ? `inset 3px 0 0 ${groupColor}` : "none",
      }}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          {step.groupKind ? (
            <p className="mb-1 text-xs font-bold uppercase" style={{ color: groupColor }}>
              {step.groupKind === "superset" ? i18n("supersetLabel") : i18n("alternatingSetsLabel")}
            </p>
          ) : null}
          <p className="text-xl font-bold leading-snug" style={{ color: "var(--text)" }}>
            {step.exercise.name}
          </p>
          {step.stepLabel ? (
            <p className="mt-0.5 text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {i18n("setLabel")} {step.stepLabel}
            </p>
          ) : null}
          {prescription || load ? (
            <div className="mt-2 flex flex-wrap items-center gap-2">
              {[prescription, load].filter(Boolean).map((chip) => (
                <span
                  key={chip}
                  className="rounded-full px-3 py-1 text-base font-semibold"
                  style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
                >
                  {chip}
                </span>
              ))}
            </div>
          ) : null}
          {step.exercise.note ? (
            <p className="mt-2 text-xs italic" style={{ color: "var(--muted)" }}>
              {step.exercise.note}
            </p>
          ) : null}
          {step.setPrescription?.note ? (
            <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
              {step.setPrescription.note}
            </p>
          ) : null}
        </div>

        <button
          type="button"
          className="min-h-11 shrink-0 rounded-xl px-3 text-xs font-semibold"
          style={{
            background: "color-mix(in srgb, var(--warning) 14%, transparent)",
            color: "var(--warning)",
            border: "1px solid color-mix(in srgb, var(--warning) 28%, transparent)",
          }}
          onClick={onModify}
        >
          {i18n("modify9fe408e")}
        </button>
      </div>

      <button
        type="button"
        onClick={onDone}
        className="mt-4 flex min-h-14 w-full items-center justify-center gap-2 rounded-xl text-base font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        <span aria-hidden="true">✓</span>
        {i18n("markStepDoneLabel")}
      </button>
    </div>
  );
}

function StepRow({
  step,
  checked,
  current,
  targetReps,
  onToggle,
}: {
  step: ChecklistStep;
  checked: boolean;
  current: boolean;
  targetReps?: number | null;
  onToggle: () => void;
}) {
  const i18n = useUiTranslations();
  const { prescription, load } = usePrescription(step, targetReps);
  const detail = [prescription, load].filter(Boolean).join(" · ");

  return (
    <li>
      <button
        type="button"
        role="checkbox"
        aria-checked={checked}
        onClick={onToggle}
        className="flex min-h-12 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
        style={{
          background: current ? "var(--panel)" : "var(--panel-muted)",
          border: `1px solid ${current ? "var(--primary)" : "var(--border)"}`,
        }}
      >
        <span
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold"
          style={
            checked
              ? { background: "var(--primary)", color: "var(--primary-contrast)" }
              : { border: "2px solid var(--dim)" }
          }
          aria-hidden="true"
        >
          {checked ? "✓" : ""}
        </span>
        <span className="min-w-0 flex-1">
          <span
            className={`block truncate text-sm font-semibold ${checked ? "line-through" : ""}`}
            style={{ color: checked ? "var(--muted)" : "var(--text)" }}
          >
            {step.exercise.name}
            {step.stepLabel ? i18n("value0Value1a19bd79", { value0: i18n("setLabel"), value1: step.stepLabel }) : ""}
          </span>
          {detail ? (
            <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>
              {detail}
            </span>
          ) : null}
        </span>
      </button>
    </li>
  );
}
