"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftExercise, DraftSection, LoadMode, PrescriptionUnit } from "@/types/workout";

import { AdvancedSettingsPanel } from "./AdvancedSettingsPanel";
import { UnitCycler } from "./UnitCycler";
import { VariationsPanel } from "./VariationsPanel";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm"];
const LOAD_LABELS: Record<LoadMode, string> = {
  absolute: "kg",
  pct_1rm: "%RM",
};

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  scaleLevels: ScaleLevel[];
  sectionOptions: Array<{ id: string; name: string }>;
};

export function ExerciseCard({ exercise, section, scaleLevels, sectionOptions }: Props) {
  const { updateExercise, toggleVariationsPanel, toggleAdvancedPanel } = useWorkoutCreationStore();
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: exercise.localId,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  function update(patch: Partial<DraftExercise>) {
    updateExercise(section.localId, exercise.localId, patch);
  }

  return (
    <div ref={setNodeRef} style={{ ...style, overflow: "visible" }}>
      <div
        className="rounded-2xl"
        style={{
          background: "var(--card)",
          border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
        }}
      >
        <div className="flex flex-wrap items-center gap-3 px-4 py-3">
          <span {...attributes} {...listeners} className="shrink-0 cursor-grab text-base" style={{ color: "var(--dim)" }}>
            ⠿
          </span>

          <input
            type="text"
            value={exercise.name}
            onChange={(event) => update({ name: event.target.value })}
            placeholder="Exercise name"
            className="min-w-[10rem] flex-1 bg-transparent text-base font-bold outline-none"
            style={{ color: "var(--text)" }}
          />

          <div className="flex items-center gap-1 shrink-0">
            <input
              type="number"
              value={exercise.sets}
              onChange={(event) => update({ sets: Number.parseInt(event.target.value, 10) || 1 })}
              className="w-8 bg-transparent text-center text-sm font-semibold outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <span className="text-sm" style={{ color: "var(--muted)" }}>
              sets
            </span>
          </div>

          <div className="flex items-center gap-1 shrink-0">
            <input
              type="number"
              value={exercise.prescriptionValue}
              onChange={(event) =>
                update({ prescriptionValue: Number.parseInt(event.target.value, 10) || 1 })
              }
              className="w-10 bg-transparent text-center text-sm font-semibold outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={PRESCRIPTION_UNITS}
              value={exercise.prescriptionUnit}
              onChange={(unit) => update({ prescriptionUnit: unit })}
            />
          </div>

          {exercise.isBodyweight ? (
            <span
              className="shrink-0 rounded-lg px-2 py-0.5 text-xs font-semibold"
              style={{ background: "var(--dim)", color: "var(--muted)" }}
            >
              BW
            </span>
          ) : (
            <div className="flex items-center gap-1 shrink-0">
              <input
                type="number"
                value={exercise.loadValue ?? ""}
                onChange={(event) =>
                  update({ loadValue: Number.parseInt(event.target.value, 10) || null })
                }
                placeholder="—"
                className="w-10 bg-transparent text-center text-sm font-semibold outline-none"
                style={{ color: "var(--text)" }}
                min={1}
              />
              <UnitCycler
                options={LOAD_MODES}
                value={exercise.loadMode}
                onChange={(mode) => update({ loadMode: mode })}
                labels={LOAD_LABELS}
              />
            </div>
          )}

          <button
            type="button"
            onClick={() => toggleVariationsPanel(section.localId, exercise.localId)}
            className="shrink-0 rounded-xl px-2 py-1 text-xs font-semibold transition-colors"
            style={{
              background: exercise.variationsOpen ? "color-mix(in srgb, var(--accent) 20%, transparent)" : "var(--bg)",
              border: "1px solid var(--dim)",
              color: exercise.variationsOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            Vars {exercise.variationsOpen ? "▲" : "▾"}
          </button>

          <button
            type="button"
            onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
            className="shrink-0 rounded-xl px-2 py-1 text-xs font-semibold transition-colors"
            style={{
              background: exercise.advancedOpen ? "color-mix(in srgb, var(--accent) 20%, transparent)" : "var(--bg)",
              border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
              color: exercise.advancedOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            ⋯
          </button>
        </div>

        {exercise.variationsOpen ? (
          <VariationsPanel exercise={exercise} section={section} scaleLevels={scaleLevels} />
        ) : null}

        {exercise.advancedOpen ? (
          <AdvancedSettingsPanel exercise={exercise} section={section} sectionOptions={sectionOptions} />
        ) : null}
      </div>
    </div>
  );
}
