"use client";

import { useState } from "react";

import type { ScaleLevel } from "@/api/workouts";
import { FORMAT_LABELS, type DraftExercise, type DraftSection, type LoadMode, type PrescriptionUnit } from "@/types/workout";

type Props = {
  section: DraftSection;
  activeScale: string | null;
  scaleLevels: ScaleLevel[];
};

function resolveExercise(
  exercise: DraftExercise,
  activeScale: string | null,
): {
  name: string;
  sets: number;
  prescriptionValue: number;
  prescriptionUnit: PrescriptionUnit;
  loadValue: number | null;
  loadMode: LoadMode;
  excluded: boolean;
  varied: boolean;
} {
  if (!activeScale) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      excluded: false,
      varied: false,
    };
  }

  const variation = exercise.variations.find((item) => item.scaleLevelSlug === activeScale);

  if (!variation) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      excluded: false,
      varied: false,
    };
  }

  if (variation.excluded) {
    return {
      name: exercise.name,
      sets: exercise.sets,
      prescriptionValue: exercise.prescriptionValue,
      prescriptionUnit: exercise.prescriptionUnit,
      loadValue: exercise.loadValue,
      loadMode: exercise.loadMode,
      excluded: true,
      varied: true,
    };
  }

  return {
    name: variation.exerciseNameOverride ?? exercise.name,
    sets: variation.sets ?? exercise.sets,
    prescriptionValue: variation.prescriptionValue ?? exercise.prescriptionValue,
    prescriptionUnit: variation.prescriptionUnit ?? exercise.prescriptionUnit,
    loadValue: variation.loadValue ?? exercise.loadValue,
    loadMode: variation.loadMode ?? exercise.loadMode,
    excluded: false,
    varied: true,
  };
}

export function PreviewSection({ section, activeScale, scaleLevels }: Props) {
  const [collapsed, setCollapsed] = useState(false);
  const isEmpty = section.exercises.length === 0;

  const params = section.formatParams;
  let formatSummary = FORMAT_LABELS[section.format];

  if (params.duration_seconds) {
    formatSummary += ` · ${Math.round((params.duration_seconds as number) / 60)} min`;
  }
  if (params.work_seconds && params.rest_seconds) {
    formatSummary += ` · ${params.work_seconds}/${params.rest_seconds}`;
  }
  if (params.rounds) {
    formatSummary += ` · ${params.rounds} rounds`;
  }

  return (
    <div className="mb-3">
      <button onClick={() => setCollapsed((current) => !current)} className="w-full py-2 text-left">
        <div className="flex items-center justify-between gap-2">
          <div>
            <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {section.name || "Unnamed section"}
            </span>
            <span className="ml-2 text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
              {formatSummary}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {isEmpty ? (
              <span className="text-xs" style={{ color: "var(--amber)" }}>
                ! no exercises
              </span>
            ) : null}
            <span className="text-xs" style={{ color: "var(--muted)" }}>
              {collapsed ? ">" : "v"}
            </span>
          </div>
        </div>
      </button>

      {!collapsed ? (
        <div className="flex flex-col gap-1 pl-2">
          {section.exercises.map((exercise) => {
            const resolved = resolveExercise(exercise, activeScale);
            const scaleLevel = activeScale ? scaleLevels.find((item) => item.slug === activeScale) : null;

            if (resolved.excluded) {
              return (
                <div
                  key={exercise.localId}
                  className="py-1 text-xs"
                  style={{ color: "var(--dim)", textDecoration: "line-through" }}
                >
                  {exercise.name}
                  {scaleLevel ? ` (${scaleLevel.label})` : ""}
                </div>
              );
            }

            return (
              <div key={exercise.localId} className="flex items-baseline gap-2 py-1 text-xs">
                <span
                  className="font-semibold"
                  style={{ color: resolved.varied ? "var(--lime)" : "var(--text)" }}
                >
                  {resolved.name || "—"}
                </span>
                <span style={{ color: "var(--muted)" }}>
                  {resolved.sets} × {resolved.prescriptionValue} {resolved.prescriptionUnit}
                  {resolved.loadValue != null
                    ? ` · ${resolved.loadValue} ${resolved.loadMode === "pct_1rm" ? "%RM" : "kg"}`
                    : ""}
                </span>
                {!resolved.varied && activeScale ? (
                  <span className="text-xs italic" style={{ color: "var(--dim)" }}>
                    (base)
                  </span>
                ) : null}
              </div>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
