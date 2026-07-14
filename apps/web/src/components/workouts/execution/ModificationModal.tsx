"use client";

import { useState } from "react";
import type { ExerciseModification } from "@/api/executions";
import type { ChecklistStep } from "./WorkoutChecklist";

type Props = {
  step: ChecklistStep;
  onSave: (mod: ExerciseModification) => void;
  onClose: () => void;
};

export function ModificationModal({ step, onSave, onClose }: Props) {
  const { exercise } = step;

  const hasPrescription =
    typeof exercise.prescription_value === "number" && exercise.prescription_value !== null;
  const hasLoad = typeof exercise.load_value === "number" && exercise.load_value !== null;
  const hasSets = typeof exercise.sets === "number" && (exercise.sets ?? 0) > 1;

  const [actualValue, setActualValue] = useState(
    hasPrescription ? String(exercise.prescription_value) : "",
  );
  const [actualLoad, setActualLoad] = useState(
    hasLoad ? String(exercise.load_value) : "",
  );
  const [actualSets, setActualSets] = useState(
    hasSets ? String(exercise.sets) : "",
  );

  function handleSkip() {
    onSave({
      exercise_id: exercise.id,
      type: "skipped",
      prescribed_value: exercise.prescription_value ?? null,
      actual_value: 0,
      prescribed_mins: null,
      actual_mins: null,
      sets: exercise.sets ?? null,
    });
  }

  function handleSave() {
    const parsedActualValue = actualValue !== "" ? Number(actualValue) : null;
    const parsedActualLoad = actualLoad !== "" ? Number(actualLoad) : null;
    const parsedActualSets = actualSets !== "" ? Number(actualSets) : null;

    const loadChanged =
      hasLoad && parsedActualLoad !== null && parsedActualLoad !== exercise.load_value;
    const repsChanged =
      hasPrescription && parsedActualValue !== null && parsedActualValue !== exercise.prescription_value;
    const type: ExerciseModification["type"] = loadChanged
      ? "weight_changed"
      : repsChanged
        ? "reps_changed"
        : "other";

    onSave({
      exercise_id: exercise.id,
      type,
      prescribed_value: exercise.prescription_value ?? null,
      actual_value: parsedActualValue,
      prescribed_mins: null,
      actual_mins: null,
      sets: parsedActualSets ?? exercise.sets ?? null,
    });
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center"
      style={{ background: "rgba(0,0,0,0.5)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-t-3xl p-6 pb-10"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-5">
          <p
            className="text-xs font-semibold uppercase tracking-[0.2em]"
            style={{ color: "var(--dim)" }}
          >
            Modify step
          </p>
          <h3 className="mt-1 text-lg font-bold" style={{ color: "var(--text)" }}>
            {exercise.name}
          </h3>
          {step.stepLabel && (
            <p className="text-sm" style={{ color: "var(--primary)" }}>
              {step.stepLabel}
            </p>
          )}
        </div>

        <div className="space-y-3 mb-6">
          {hasSets && (
            <div>
              <label className="block text-xs font-semibold mb-1" style={{ color: "var(--muted)" }}>
                Sets (prescribed: {exercise.sets})
              </label>
              <input
                type="number"
                inputMode="numeric"
                className="w-full rounded-xl px-4 py-2.5 text-sm font-semibold outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                value={actualSets}
                onChange={(e) => setActualSets(e.target.value)}
                placeholder={String(exercise.sets)}
              />
            </div>
          )}

          {hasPrescription && (
            <div>
              <label className="block text-xs font-semibold mb-1" style={{ color: "var(--muted)" }}>
                {exercise.prescription_unit
                  ? `${exercise.prescription_unit} (prescribed: ${exercise.prescription_value})`
                  : `Reps / value (prescribed: ${exercise.prescription_value})`}
              </label>
              <input
                type="number"
                inputMode="numeric"
                className="w-full rounded-xl px-4 py-2.5 text-sm font-semibold outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                value={actualValue}
                onChange={(e) => setActualValue(e.target.value)}
                placeholder={String(exercise.prescription_value)}
              />
            </div>
          )}

          {hasLoad && (
            <div>
              <label className="block text-xs font-semibold mb-1" style={{ color: "var(--muted)" }}>
                {exercise.load_mode === "pct_1rm"
                  ? `Load % RM (prescribed: ${exercise.load_value}%)`
                  : `Load kg (prescribed: ${exercise.load_value} kg)`}
              </label>
              <input
                type="number"
                inputMode="decimal"
                className="w-full rounded-xl px-4 py-2.5 text-sm font-semibold outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                value={actualLoad}
                onChange={(e) => setActualLoad(e.target.value)}
                placeholder={String(exercise.load_value)}
              />
            </div>
          )}

          {!hasPrescription && !hasLoad && !hasSets && (
            <p className="text-sm py-2" style={{ color: "var(--dim)" }}>
              No prescribed values for this exercise. Use the skip button if you didn't do it.
            </p>
          )}
        </div>

        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={handleSave}
            className="w-full rounded-2xl py-3.5 text-base font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
          >
            Save changes
          </button>
          <button
            type="button"
            onClick={handleSkip}
            className="w-full rounded-2xl py-3.5 text-base font-semibold"
            style={{
              background: "color-mix(in srgb, var(--danger, var(--primary)) 12%, transparent)",
              color: "var(--danger, var(--primary))",
              border: "1px solid color-mix(in srgb, var(--danger, var(--primary)) 25%, transparent)",
            }}
          >
            I skipped this step completely
          </button>
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-2xl py-3 text-sm font-semibold"
            style={{ color: "var(--dim)" }}
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}
