"use client";



import {useUiTranslations} from "@/i18n/ui";
import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftExercise, DraftSection, LoadMode, PrescriptionUnit } from "@/types/workout";

import { UnitCycler } from "./UnitCycler";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm", "bw"];
const LOAD_LABELS: Record<LoadMode, string> = {
  absolute: "kg",
  pct_1rm: "%RM",
  bw: "BW",
};

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  scaleLevels: ScaleLevel[];
};

export function VariationsPanel({ exercise, section, scaleLevels }: Props) {
  const i18n = useUiTranslations();
  const { addVariation, updateVariation, excludeVariation, restoreVariation } = useWorkoutCreationStore();

  const scalesWithoutVariation = scaleLevels.filter(
    (scaleLevel) => !exercise.variations.some((variation) => variation.scaleLevelSlug === scaleLevel.slug),
  );

  return (
    <div className="border-t px-4 pb-4" style={{ borderColor: "var(--dim)" }}>
      <div className="flex items-center justify-between py-2">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          {i18n("scaleVariationsb4decb5")}
        </span>
        {scalesWithoutVariation.length > 0 ? (
          <div className="flex flex-wrap gap-1">
            {scalesWithoutVariation.map((scaleLevel) => (
              <button
                key={scaleLevel.slug}
                onClick={() => addVariation(section.localId, exercise.localId, scaleLevel.slug)}
                className="rounded-lg px-2 py-0.5 text-xs"
                style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--muted)" }}
              >
                + {scaleLevel.label}
              </button>
            ))}
          </div>
        ) : null}
      </div>

      {exercise.variations.map((variation) => {
        const scaleLevel = scaleLevels.find((item) => item.slug === variation.scaleLevelSlug);
        if (!scaleLevel) return null;

        if (variation.excluded) {
          return (
            <div key={variation.scaleLevelSlug} className="flex items-center gap-3 py-2">
              <span className="w-20 shrink-0 text-xs" style={{ color: "var(--muted)" }}>
                {scaleLevel.label}
              </span>
              <span className="flex-1 text-xs italic" style={{ color: "var(--dim)" }}>
                {i18n("excludedForThisScalecb1b1ce")}
              </span>
              <button
                onClick={() => restoreVariation(section.localId, exercise.localId, scaleLevel.slug)}
                className="text-xs"
                style={{ color: "var(--muted)" }}
              >
                {i18n("restore3cbe6d6")}
              </button>
            </div>
          );
        }

        return (
          <div key={variation.scaleLevelSlug} className="flex flex-wrap items-center gap-2 py-2">
            <span className="w-20 shrink-0 text-xs font-semibold" style={{ color: "var(--muted)" }}>
              {scaleLevel.label}
            </span>

            <input
              type="text"
              value={variation.exerciseNameOverride ?? exercise.name}
              onChange={(event) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  exerciseNameOverride: event.target.value === exercise.name ? null : event.target.value,
                })
              }
              className="min-w-[6rem] flex-1 border-b border-transparent bg-transparent text-sm outline-none transition-colors focus:border-current"
              style={{ color: "var(--dim)" }}
            />

            <input
              type="number"
              value={variation.sets ?? exercise.sets}
              onChange={(event) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  sets: Number.parseInt(event.target.value, 10) || null,
                })
              }
              className="w-8 bg-transparent text-center text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <span className="text-xs" style={{ color: "var(--muted)" }}>
              {i18n("setsd6c8220")}
            </span>

            <input
              type="number"
              value={variation.prescriptionValue ?? exercise.prescriptionValue}
              onChange={(event) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  prescriptionValue: Number.parseInt(event.target.value, 10) || null,
                })
              }
              className="w-10 bg-transparent text-center text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={PRESCRIPTION_UNITS}
              value={variation.prescriptionUnit ?? exercise.prescriptionUnit}
              onChange={(unit) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  prescriptionUnit: unit,
                })
              }
            />

            <input
              type="number"
              value={variation.loadValue ?? exercise.loadValue ?? ""}
              onChange={(event) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  loadValue: Number.parseInt(event.target.value, 10) || null,
                })
              }
              placeholder="—"
              className="w-10 bg-transparent text-center text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={LOAD_MODES}
              value={variation.loadMode ?? exercise.loadMode}
              onChange={(mode) =>
                updateVariation(section.localId, exercise.localId, scaleLevel.slug, {
                  loadMode: mode,
                })
              }
              labels={LOAD_LABELS}
            />

            <button
              onClick={() => excludeVariation(section.localId, exercise.localId, scaleLevel.slug)}
              className="ml-auto text-sm transition-colors"
              style={{ color: "var(--dim)" }}
              title={i18n("excludeThisExerciseForThisScaleLevele23e9bd")}
            >
              ⊘
            </button>
          </div>
        );
      })}

      {exercise.variations.length === 0 ? (
        <p className="py-2 text-xs" style={{ color: "var(--dim)" }}>
          {i18n("noScaleVariationsDefinedAllAthletesUseThe6a8612c")}
        </p>
      ) : null}
    </div>
  );
}
