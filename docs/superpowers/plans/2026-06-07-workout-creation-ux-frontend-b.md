# Workout Creation Canvas — Frontend Tasks (17–24)

Part of: [Main plan](./2026-06-07-workout-creation-ux.md)

Prerequisite: [Frontend tasks 8–16](./2026-06-07-workout-creation-ux-frontend-a.md) complete.

---

## Task 17: Exercise Card + UnitCycler

**Files:**
- Create: `apps/web/src/components/workouts/creation/UnitCycler.tsx`
- Create: `apps/web/src/components/workouts/creation/ExerciseCard.tsx`

- [ ] **Step 1: Write `UnitCycler.tsx`**

```tsx
"use client";

type UnitCyclerProps<T extends string> = {
  options: T[];
  value: T;
  onChange: (next: T) => void;
};

export function UnitCycler<T extends string>({ options, value, onChange }: UnitCyclerProps<T>) {
  function cycle() {
    const idx = options.indexOf(value);
    onChange(options[(idx + 1) % options.length]);
  }

  return (
    <button
      type="button"
      onClick={cycle}
      className="text-sm font-medium transition-colors cursor-pointer select-none"
      style={{ color: "var(--muted)" }}
      title={`Click to cycle: ${options.join(" → ")}`}
    >
      {value}
    </button>
  );
}
```

- [ ] **Step 2: Write `ExerciseCard.tsx`**

```tsx
"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { DraftExercise, DraftSection, PrescriptionUnit, LoadMode } from "@/types/workout";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { UnitCycler } from "./UnitCycler";
import { VariationsPanel } from "./VariationsPanel";
import { AdvancedSettingsPanel } from "./AdvancedSettingsPanel";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm"];
const LOAD_UNIT_LABELS: Record<LoadMode, string> = {
  absolute: "kg",
  pct_1rm: "%RM",
};

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
};

export function ExerciseCard({ exercise, section }: Props) {
  const { updateExercise, toggleVariationsPanel, toggleAdvancedPanel } =
    useWorkoutCreationStore();

  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: exercise.localId });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  function update(patch: Partial<DraftExercise>) {
    updateExercise(section.localId, exercise.localId, patch);
  }

  return (
    <div
      ref={setNodeRef}
      style={{
        ...style,
        overflow: "visible", // let panels escape
      }}
    >
      <div
        className="rounded-2xl"
        style={{
          background: "var(--card)",
          border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
        }}
      >
        {/* Base row */}
        <div className="flex items-center gap-3 px-4 py-3">
          {/* Drag handle */}
          <span
            {...attributes}
            {...listeners}
            className="cursor-grab text-base shrink-0"
            style={{ color: "var(--dim)" }}
          >
            ⠿
          </span>

          {/* Exercise name */}
          <input
            type="text"
            value={exercise.name}
            onChange={(e) => update({ name: e.target.value })}
            placeholder="Exercise name"
            className="flex-1 bg-transparent text-base font-bold outline-none min-w-0"
            style={{ color: "var(--text)" }}
          />

          {/* Sets */}
          <div className="flex items-center gap-1 shrink-0">
            <input
              type="number"
              value={exercise.sets}
              onChange={(e) => update({ sets: parseInt(e.target.value, 10) || 1 })}
              className="w-8 text-center bg-transparent outline-none text-sm font-semibold"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <span className="text-sm" style={{ color: "var(--muted)" }}>sets</span>
          </div>

          {/* Prescription: value + cycling unit */}
          <div className="flex items-center gap-1 shrink-0">
            <input
              type="number"
              value={exercise.prescriptionValue}
              onChange={(e) => update({ prescriptionValue: parseInt(e.target.value, 10) || 1 })}
              className="w-10 text-center bg-transparent outline-none text-sm font-semibold"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={PRESCRIPTION_UNITS}
              value={exercise.prescriptionUnit}
              onChange={(unit) => update({ prescriptionUnit: unit })}
            />
          </div>

          {/* Load: value + cycling unit (or BW badge) */}
          {exercise.isBodyweight ? (
            <span className="text-xs font-semibold px-2 py-0.5 rounded-lg shrink-0" style={{ background: "var(--dim)", color: "var(--muted)" }}>
              BW
            </span>
          ) : (
            <div className="flex items-center gap-1 shrink-0">
              <input
                type="number"
                value={exercise.loadValue ?? ""}
                onChange={(e) => update({ loadValue: parseInt(e.target.value, 10) || null })}
                placeholder="—"
                className="w-10 text-center bg-transparent outline-none text-sm font-semibold"
                style={{ color: "var(--text)" }}
                min={1}
              />
              <UnitCycler
                options={LOAD_MODES}
                value={exercise.loadMode}
                onChange={(mode) => update({ loadMode: mode })}
              />
            </div>
          )}

          {/* Vars toggle */}
          <button
            type="button"
            onClick={() => toggleVariationsPanel(section.localId, exercise.localId)}
            className="shrink-0 text-xs font-semibold rounded-xl px-2 py-1 transition-colors"
            style={{
              background: exercise.variationsOpen ? "var(--accent)33" : "var(--bg)",
              border: "1px solid var(--dim)",
              color: exercise.variationsOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            Vars {exercise.variationsOpen ? "▲" : "▾"}
          </button>

          {/* Advanced toggle */}
          <button
            type="button"
            onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
            className="shrink-0 text-xs font-semibold rounded-xl px-2 py-1 transition-colors"
            style={{
              background: exercise.advancedOpen ? "var(--accent)33" : "var(--bg)",
              border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
              color: exercise.advancedOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            ⋯
          </button>
        </div>

        {/* Variations panel */}
        {exercise.variationsOpen && (
          <VariationsPanel exercise={exercise} section={section} />
        )}

        {/* Advanced settings panel */}
        {exercise.advancedOpen && (
          <AdvancedSettingsPanel exercise={exercise} section={section} />
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/creation/UnitCycler.tsx \
        apps/web/src/components/workouts/creation/ExerciseCard.tsx
git commit -m "feat(web/canvas): add ExerciseCard with unit cycling and panel toggles"
```

---

## Task 18: Variations Panel

**Files:**
- Create: `apps/web/src/components/workouts/creation/VariationsPanel.tsx`

- [ ] **Step 1: Write the component**

The panel assumes that `ScaleLevel[]` is passed in from the parent (the parent fetches scale levels). For now, the panel needs scale level data. We'll thread it through props from the MiddlePanel → ExerciseCard → VariationsPanel.

Update `ExerciseCard` props to include `scaleLevels: ScaleLevel[]` and thread down.

```tsx
"use client";

import type { DraftExercise, DraftSection, PrescriptionUnit, LoadMode } from "@/types/workout";
import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { UnitCycler } from "./UnitCycler";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm"];

const SCALE_EMOJI: Record<string, string> = {};

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  scaleLevels: ScaleLevel[];
};

export function VariationsPanel({ exercise, section, scaleLevels }: Props) {
  const { addVariation, updateVariation, excludeVariation, restoreVariation } =
    useWorkoutCreationStore();

  const scalesWithoutVariation = scaleLevels.filter(
    (sl) => !exercise.variations.some((v) => v.scaleLevelSlug === sl.slug)
  );

  return (
    <div
      className="px-4 pb-4 border-t"
      style={{ borderColor: "var(--dim)" }}
    >
      {/* Panel header */}
      <div className="flex items-center justify-between py-2">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Scale Variations
        </span>
        {scalesWithoutVariation.length > 0 && (
          <div className="flex gap-1">
            {scalesWithoutVariation.map((sl) => (
              <button
                key={sl.slug}
                onClick={() => addVariation(section.localId, exercise.localId, sl.slug)}
                className="text-xs px-2 py-0.5 rounded-lg"
                style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--muted)" }}
              >
                + {sl.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Variation rows */}
      {exercise.variations.map((variation) => {
        const sl = scaleLevels.find((s) => s.slug === variation.scaleLevelSlug);
        if (!sl) return null;

        if (variation.excluded) {
          return (
            <div key={variation.scaleLevelSlug} className="flex items-center gap-3 py-2">
              <span className="text-xs w-20 shrink-0" style={{ color: "var(--muted)" }}>
                {sl.label}
              </span>
              <span className="flex-1 text-xs italic" style={{ color: "var(--dim)" }}>
                Excluded for this scale
              </span>
              <button
                onClick={() => restoreVariation(section.localId, exercise.localId, sl.slug)}
                className="text-xs"
                style={{ color: "var(--muted)" }}
              >
                ↩ Restore
              </button>
            </div>
          );
        }

        return (
          <div key={variation.scaleLevelSlug} className="flex items-center gap-2 py-2">
            {/* Scale label */}
            <span className="text-xs font-semibold w-20 shrink-0" style={{ color: "var(--muted)" }}>
              {sl.label}
            </span>

            {/* Exercise name override */}
            <input
              type="text"
              value={variation.exerciseNameOverride ?? exercise.name}
              onChange={(e) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  exerciseNameOverride:
                    e.target.value === exercise.name ? null : e.target.value,
                })
              }
              className="w-28 bg-transparent text-sm outline-none border-b border-transparent focus:border-current transition-colors"
              style={{ color: "var(--dim)" }}
            />

            {/* Sets */}
            <input
              type="number"
              value={variation.sets ?? exercise.sets}
              onChange={(e) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  sets: parseInt(e.target.value, 10) || null,
                })
              }
              className="w-8 text-center bg-transparent text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <span className="text-xs" style={{ color: "var(--muted)" }}>sets</span>

            {/* Prescription */}
            <input
              type="number"
              value={variation.prescriptionValue ?? exercise.prescriptionValue}
              onChange={(e) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  prescriptionValue: parseInt(e.target.value, 10) || null,
                })
              }
              className="w-10 text-center bg-transparent text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={PRESCRIPTION_UNITS}
              value={variation.prescriptionUnit ?? exercise.prescriptionUnit}
              onChange={(unit) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  prescriptionUnit: unit,
                })
              }
            />

            {/* Load */}
            <input
              type="number"
              value={variation.loadValue ?? exercise.loadValue ?? ""}
              onChange={(e) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  loadValue: parseInt(e.target.value, 10) || null,
                })
              }
              placeholder="—"
              className="w-10 text-center bg-transparent text-sm outline-none"
              style={{ color: "var(--text)" }}
              min={1}
            />
            <UnitCycler
              options={LOAD_MODES}
              value={variation.loadMode ?? exercise.loadMode}
              onChange={(mode) =>
                updateVariation(section.localId, exercise.localId, sl.slug, {
                  loadMode: mode,
                })
              }
            />

            {/* Exclude button — pushed far right */}
            <button
              onClick={() => excludeVariation(section.localId, exercise.localId, sl.slug)}
              className="ml-auto text-sm transition-colors"
              style={{ color: "var(--dim)" }}
              title="Exclude this exercise for this scale level"
              onMouseEnter={(e) => ((e.target as HTMLElement).style.color = "var(--red)")}
              onMouseLeave={(e) => ((e.target as HTMLElement).style.color = "var(--dim)")}
            >
              ⊘
            </button>
          </div>
        );
      })}

      {exercise.variations.length === 0 && (
        <p className="text-xs py-2" style={{ color: "var(--dim)" }}>
          No scale variations defined. All athletes use the base prescription.
        </p>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/workouts/creation/VariationsPanel.tsx
git commit -m "feat(web/canvas): add VariationsPanel with name override, unit cycling, exclude"
```

---

## Task 19: Advanced Settings Panel

**Files:**
- Create: `apps/web/src/components/workouts/creation/AdvancedSettingsPanel.tsx`

- [ ] **Step 1: Write the component**

```tsx
"use client";

import type { DraftExercise, DraftSection } from "@/types/workout";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

type SettingKey = keyof DraftExercise["advanced"];

const SETTINGS: {
  key: SettingKey;
  label: string;
  unit: string;
  inputType: "number" | "text";
  placeholder: string;
}[] = [
  { key: "hrZone", label: "Heart Rate Zone", unit: "Zone", inputType: "number", placeholder: "3" },
  { key: "tempo", label: "Tempo (ecc–pause–con–top)", unit: "", inputType: "text", placeholder: "3-1-2-0" },
  { key: "restSeconds", label: "Rest Between Sets", unit: "secs", inputType: "number", placeholder: "90" },
  { key: "clusterRestSeconds", label: "Cluster Sets Intra-Rest", unit: "secs", inputType: "number", placeholder: "15" },
  { key: "restPauseSeconds", label: "Rest-Pause", unit: "secs", inputType: "number", placeholder: "20" },
  { key: "pacing", label: "Pacing", unit: "/km", inputType: "number", placeholder: "300" },
];

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
};

export function AdvancedSettingsPanel({ exercise, section }: Props) {
  const {
    toggleAdvancedPanel,
    toggleAdvancedSetting,
    updateAdvancedValue,
    deleteExercise,
  } = useWorkoutCreationStore();

  return (
    <div
      className="px-4 pb-4 border-t"
      style={{ borderColor: "var(--accent)" }}
    >
      {/* Panel header */}
      <div className="flex items-center justify-between py-2">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Advanced Settings
        </span>
        <button
          onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
          className="text-xs"
          style={{ color: "var(--muted)" }}
        >
          ✕ Close
        </button>
      </div>

      {/* Settings rows */}
      <div className="flex flex-col gap-1">
        {SETTINGS.map(({ key, label, unit, inputType, placeholder }) => {
          const setting = exercise.advanced[key];
          return (
            <div key={key} className="flex items-center gap-3 py-1.5">
              {/* Toggle — ONLY this element changes the enabled state */}
              <button
                type="button"
                onClick={() => toggleAdvancedSetting(section.localId, exercise.localId, key)}
                className="relative w-8 h-4 rounded-full transition-colors shrink-0"
                style={{ background: setting.enabled ? "var(--accent)" : "var(--dim)" }}
              >
                <span
                  className="absolute top-0.5 w-3 h-3 rounded-full bg-white transition-transform"
                  style={{ transform: setting.enabled ? "translateX(18px)" : "translateX(2px)" }}
                />
              </button>

              {/* Label — click does NOT toggle */}
              <span
                className="flex-1 text-sm"
                style={{ color: setting.enabled ? "var(--text)" : "var(--muted)" }}
              >
                {label}
              </span>

              {/* Input — only visible when enabled; click does NOT toggle */}
              {setting.enabled && (
                <div className="flex items-center gap-2 shrink-0">
                  <input
                    type={inputType}
                    value={setting.value}
                    onChange={(e) =>
                      updateAdvancedValue(
                        section.localId,
                        exercise.localId,
                        key,
                        inputType === "number"
                          ? parseInt(e.target.value, 10) || 0
                          : e.target.value
                      )
                    }
                    className="w-16 text-right rounded-lg px-2 py-1 text-sm outline-none"
                    style={{
                      background: "var(--bg)",
                      border: "1px solid var(--dim)",
                      color: "var(--text)",
                    }}
                  />
                  {unit && (
                    <span className="text-sm" style={{ color: "var(--muted)" }}>{unit}</span>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Destructive action — remove exercise */}
      <button
        onClick={() => deleteExercise(section.localId, exercise.localId)}
        className="mt-4 text-xs font-semibold"
        style={{ color: "var(--red)" }}
      >
        ✕ Remove exercise
      </button>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/workouts/creation/AdvancedSettingsPanel.tsx
git commit -m "feat(web/canvas): add AdvancedSettingsPanel with toggle-driven settings"
```

---

## Task 20: Right Panel — Preview

**Files:**
- Create: `apps/web/src/components/workouts/creation/RightPanel.tsx`
- Create: `apps/web/src/components/workouts/creation/PreviewSection.tsx`

- [ ] **Step 1: Write `PreviewSection.tsx`**

```tsx
"use client";

import { useState } from "react";
import type { DraftSection, DraftExercise, DraftVariation, PrescriptionUnit, LoadMode } from "@/types/workout";
import type { ScaleLevel } from "@/api/workouts";
import { FORMAT_LABELS } from "@/types/workout";

type Props = {
  section: DraftSection;
  activeScale: string | null; // null = base
  scaleLevels: ScaleLevel[];
};

function resolveExercise(
  exercise: DraftExercise,
  activeScale: string | null
): { name: string; sets: number; prescriptionValue: number; prescriptionUnit: PrescriptionUnit; loadValue: number | null; loadMode: LoadMode; excluded: boolean; varied: boolean } {
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

  const variation = exercise.variations.find((v) => v.scaleLevelSlug === activeScale);
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

  const formatLabel = FORMAT_LABELS[section.format];
  const params = section.formatParams;
  let formatSummary = formatLabel;
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
      {/* Section header */}
      <button
        onClick={() => setCollapsed((c) => !c)}
        className="w-full flex items-center justify-between py-2 text-left"
      >
        <div>
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
            {section.name || "Unnamed section"}
          </span>
          <span className="ml-2 text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            {formatSummary}
          </span>
        </div>
        <div className="flex items-center gap-2">
          {isEmpty && (
            <span className="text-xs" style={{ color: "var(--amber)" }}>⚠ no exercises</span>
          )}
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {collapsed ? "›" : "∨"}
          </span>
        </div>
      </button>

      {/* Exercises */}
      {!collapsed && (
        <div className="flex flex-col gap-1 pl-2">
          {section.exercises.map((exercise) => {
            const resolved = resolveExercise(exercise, activeScale);

            if (resolved.excluded) {
              return (
                <div
                  key={exercise.localId}
                  className="text-xs py-1"
                  style={{ color: "var(--dim)", textDecoration: "line-through" }}
                >
                  {exercise.name}
                </div>
              );
            }

            const loadUnit = resolved.loadMode === "pct_1rm" ? "%RM" : "kg";

            return (
              <div key={exercise.localId} className="flex items-baseline gap-2 text-xs py-1">
                <span
                  className="font-semibold"
                  style={{ color: resolved.varied ? "var(--lime)" : "var(--text)" }}
                >
                  {resolved.name || "—"}
                </span>
                <span style={{ color: "var(--muted)" }}>
                  {resolved.sets} × {resolved.prescriptionValue} {resolved.prescriptionUnit}
                  {resolved.loadValue != null && ` · ${resolved.loadValue} ${loadUnit}`}
                </span>
                {!resolved.varied && activeScale && (
                  <span className="text-xs italic" style={{ color: "var(--dim)" }}>(base)</span>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Write `RightPanel.tsx`**

```tsx
"use client";

import { useState } from "react";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { PreviewSection } from "./PreviewSection";
import type { ScaleLevel } from "@/api/workouts";

type Props = {
  scaleLevels: ScaleLevel[];
};

export function RightPanel({ scaleLevels }: Props) {
  const { sections, rightCollapsed, setRightCollapsed } = useWorkoutCreationStore();
  const [activeScale, setActiveScale] = useState<string | null>(null);

  if (rightCollapsed) {
    return (
      <div
        className="flex flex-col items-center justify-center w-10 shrink-0 cursor-pointer"
        style={{ background: "var(--panel)", borderLeft: "1px solid var(--dim)" }}
        onClick={() => setRightCollapsed(false)}
      >
        <span
          className="text-xs font-bold tracking-widest uppercase"
          style={{
            writingMode: "vertical-rl",
            color: "var(--muted)",
          }}
        >
          Preview
        </span>
        <span className="mt-2 text-xs" style={{ color: "var(--muted)" }}>‹</span>
      </div>
    );
  }

  // Collect all scale levels that appear in any variation
  const activeScales = scaleLevels.filter((sl) =>
    sections.some((section) =>
      section.exercises.some((e) =>
        e.variations.some((v) => v.scaleLevelSlug === sl.slug)
      )
    )
  );

  return (
    <div
      className="flex flex-col w-72 shrink-0 overflow-hidden"
      style={{ background: "var(--panel)", borderLeft: "1px solid var(--dim)" }}
    >
      {/* Panel header */}
      <div className="flex items-center justify-between px-4 py-3 shrink-0">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Preview
        </span>
        <button
          onClick={() => setRightCollapsed(true)}
          className="text-xs"
          style={{ color: "var(--dim)" }}
        >
          ›
        </button>
      </div>

      {/* Scale tabs */}
      <div className="flex gap-1 px-4 pb-3 shrink-0 flex-wrap">
        <button
          onClick={() => setActiveScale(null)}
          className="text-xs px-3 py-1 rounded-2xl font-semibold transition-colors"
          style={{
            background: activeScale === null ? "var(--lime)" : "var(--card)",
            color: activeScale === null ? "#0A0A0F" : "var(--muted)",
          }}
        >
          Base
        </button>
        {activeScales.map((sl) => (
          <button
            key={sl.slug}
            onClick={() => setActiveScale(sl.slug)}
            className="text-xs px-3 py-1 rounded-2xl font-semibold transition-colors"
            style={{
              background: activeScale === sl.slug ? "var(--lime)" : "var(--card)",
              color: activeScale === sl.slug ? "#0A0A0F" : "var(--muted)",
            }}
          >
            {sl.label}
          </button>
        ))}
      </div>

      {/* Sections list — scrollable */}
      <div className="flex-1 overflow-y-auto px-4">
        {sections.length === 0 ? (
          <p className="text-xs py-4 text-center" style={{ color: "var(--dim)" }}>
            Add sections to see preview
          </p>
        ) : (
          sections.map((section) => (
            <PreviewSection
              key={section.localId}
              section={section}
              activeScale={activeScale}
              scaleLevels={scaleLevels}
            />
          ))
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Update `WorkoutCreationCanvas` to pass `scaleLevels` to `RightPanel` and `MiddlePanel`**

The canvas needs to fetch scale levels on mount and pass them down. Update the canvas:

```tsx
// Add to WorkoutCreationCanvas.tsx:
const [scaleLevels, setScaleLevels] = useState<ScaleLevel[]>([]);

useEffect(() => {
  if (!tokens?.access_token) return;
  listScaleLevels(tokens.access_token).then(setScaleLevels).catch(() => {});
}, [tokens?.access_token]);

// Pass scaleLevels to RightPanel and MiddlePanel (thread through props)
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/workouts/creation/RightPanel.tsx \
        apps/web/src/components/workouts/creation/PreviewSection.tsx
git commit -m "feat(web/canvas): add RightPanel preview with scale tabs and live sync"
```

---

## Task 21: Mobile Layout

**Files:**
- Modify: `apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx`

The mobile layout uses CSS breakpoints to switch from 3-panel to sequential drill-down.

- [ ] **Step 1: Add mobile view state to store**

Add to `workout-creation.ts`:

```typescript
// In store state:
mobileView: "sections" | "exercises" | "preview";
setMobileView: (view: "sections" | "exercises" | "preview") => void;
```

Add implementation:
```typescript
mobileView: "sections",
setMobileView: (mobileView) => set({ mobileView }),
```

- [ ] **Step 2: Add responsive classes to `WorkoutCreationCanvas`**

Wrap panels in a responsive structure:

```tsx
{/* Desktop: 3-panel side by side */}
<div className="hidden md:flex flex-1 overflow-hidden">
  <LeftPanel scaleLevels={scaleLevels} />
  <MiddlePanel scaleLevels={scaleLevels} />
  <RightPanel scaleLevels={scaleLevels} />
</div>

{/* Mobile: single view at a time */}
<div className="flex md:hidden flex-1 overflow-hidden flex-col">
  <MobileCanvas scaleLevels={scaleLevels} />
</div>
```

- [ ] **Step 3: Create `MobileCanvas.tsx`**

```tsx
"use client";

import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { LeftPanel } from "./LeftPanel";
import { MiddlePanel } from "./MiddlePanel";
import { RightPanel } from "./RightPanel";
import type { ScaleLevel } from "@/api/workouts";

type Props = { scaleLevels: ScaleLevel[] };

export function MobileCanvas({ scaleLevels }: Props) {
  const { mobileView, setMobileView, selectedSectionId } = useWorkoutCreationStore();

  return (
    <div className="flex flex-col flex-1 overflow-hidden relative">
      {/* Back navigation */}
      {mobileView === "exercises" && (
        <button
          onClick={() => setMobileView("sections")}
          className="px-4 py-2 text-sm text-left"
          style={{ color: "var(--accent)" }}
        >
          ‹ Sections
        </button>
      )}

      {/* Active panel */}
      <div className="flex-1 overflow-hidden">
        {mobileView === "sections" && (
          <LeftPanel
            scaleLevels={scaleLevels}
            onSectionSelected={() => setMobileView("exercises")}
          />
        )}
        {mobileView === "exercises" && (
          <MiddlePanel scaleLevels={scaleLevels} />
        )}
        {mobileView === "preview" && (
          <RightPanel scaleLevels={scaleLevels} />
        )}
      </div>

      {/* Bottom bar */}
      <div
        className="flex border-t shrink-0"
        style={{ borderColor: "var(--dim)", background: "var(--panel)" }}
      >
        {(["sections", "exercises"] as const).map((view) => (
          <button
            key={view}
            onClick={() => setMobileView(view)}
            className="flex-1 py-3 text-xs font-bold uppercase tracking-widest"
            style={{ color: mobileView === view ? "var(--accent)" : "var(--dim)" }}
          >
            {view}
          </button>
        ))}
        <button
          onClick={() => setMobileView("preview")}
          className="flex-1 py-3 text-xs font-bold uppercase tracking-widest"
          style={{ color: mobileView === "preview" ? "var(--lime)" : "var(--dim)" }}
        >
          Preview
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/workouts/creation/MobileCanvas.tsx
git commit -m "feat(web/canvas): add mobile drill-down layout"
```

---

## Task 22: Wire Up Page + Remove Old WorkoutForm

**Files:**
- Modify: `apps/web/src/app/admin/workouts/new/page.tsx`
- Modify: `apps/web/src/components/workouts/WorkoutAdminConsole.tsx`

- [ ] **Step 1: Update `new/page.tsx` to use new canvas directly**

```tsx
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";

export const dynamic = "force-dynamic";

export default function NewWorkoutPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutCreationCanvas />
    </AuthGuard>
  );
}
```

- [ ] **Step 2: Remove `mode="new"` branch from `WorkoutAdminConsole.tsx`**

`WorkoutAdminConsole` only handles `mode="index"` now (the list view). Remove all references to `WorkoutForm` from the `"new"` branch since that route is handled directly by the canvas.

If `WorkoutAdminConsole` only has index mode remaining and WorkoutForm is no longer needed, `WorkoutForm.tsx` can be deleted:

```bash
rm apps/web/src/components/workouts/WorkoutForm.tsx
```

Clean up imports in `WorkoutAdminConsole.tsx` if WorkoutForm was imported.

- [ ] **Step 3: Verify the build**

```bash
cd apps/web && npm run build 2>&1 | tail -20
```

Expected: build succeeds with no errors.

If there are TypeScript errors (e.g., `scaleLevels` prop threading inconsistencies), fix them before committing.

- [ ] **Step 4: Run format + lint**

```bash
cd apps/web && npm run lint
```

Fix any lint errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/app/admin/workouts/new/page.tsx \
        apps/web/src/components/workouts/WorkoutAdminConsole.tsx
git rm apps/web/src/components/workouts/WorkoutForm.tsx
git commit -m "feat(web): wire WorkoutCreationCanvas to /admin/workouts/new, remove old WorkoutForm"
```

---

## Task 23: Self-Review Checklist

Run through the spec against the implementation before considering this plan complete.

- [ ] **Header:** title input, type selector, completion text ("N of M sections complete"), save status (↻/✓/⚠), publish button with tooltip listing missing fields
- [ ] **Left panel:** sortable section chips with `✓`/`!` badges, `[+ Add section]` button, section config shown only when a section is selected, config disappears on click-away
- [ ] **Format dropdown:** custom (not `<select>`), grouped options, hover tooltips with Best For / Trains / How / Score, auto-score silently pre-applied
- [ ] **Contextual fields:** number-only inputs, adjacent unit labels (not inside field), real default values, optional fields labeled
- [ ] **Exercise card:** single-line base row, drag handle always visible, `[Vars ▾]` / `[⋯]` buttons, unit cycling (one unit at a time)
- [ ] **BW indicator:** bodyweight exercises show `BW` badge instead of load input
- [ ] **Variations panel:** inline below row, exercise name pre-filled in grey editable text, `⊘` pushed to far right with `margin-left: auto`
- [ ] **Advanced panel:** labels always visible, inputs show only when toggle ON, toggle is the ONLY click target — clicking label/input does NOT toggle
- [ ] **Preview panel:** scale tabs at top, varied values in lime, unchanged values muted with `(base)`, excluded exercises crossed out
- [ ] **Save flow:** PATCH debounced 1.5 s after any change, status indicator cycles through saving/saved/error
- [ ] **Publish:** disabled until title + type + all sections valid; on success redirects to `/admin/workouts`
- [ ] **Mobile:** sections → exercises → preview drill-down, bottom nav bar
- [ ] **Drag and drop:** sections sortable in left panel, exercises sortable in middle panel, mobile cross-section via advanced panel "Move to section →" action (note: this action is not yet in the spec's advanced settings panel — add a `moveToSection` select in `AdvancedSettingsPanel` for mobile)
- [ ] **All panels independently scrollable:** left panel body, middle exercise list, right panel preview each have `overflow-y: auto`
- [ ] **Section config hides on click-away:** implement a `useEffect` in `LeftPanel` that adds a global click listener and calls `selectSection(null)` when clicking outside the left panel

- [ ] **Fix any gaps found in the self-review above before marking plan complete**

---

## Task 24: Final Quality Pass

- [ ] **Backend:**

```bash
cd apps/api && mix test && mix format && mix credo --strict
```

Fix all failures and warnings.

- [ ] **Frontend:**

```bash
cd apps/web && npm run build && npm run lint && npx tsc --noEmit
```

Fix all errors.

- [ ] **Smoke test the full flow:**

1. Navigate to `/admin/workouts/new`
2. Verify canvas loads (no errors in console)
3. Verify draft is created (network tab: `POST /api/admin/workouts` → 201)
4. Add a title → wait 1.5 s → verify `PATCH /api/admin/workouts/:id/draft` → 200
5. Add a section, set a name and format
6. Add exercises, set names, sets, prescription, load
7. Open variations panel, add a variation
8. Open advanced settings panel, enable a toggle
9. Verify preview updates live
10. Click Publish → verify `POST /api/admin/workouts/:id/publish` → 200
11. Verify redirect to `/admin/workouts`

- [ ] **Write ADR**

Create `docs/adr/YYYY-MM-DD-workout-canvas-architecture.md` documenting:
- Context: Phase 2 hardening, frontend-first redesign
- Decision: 3-panel canvas, draft/publish flow, `draft_data` JSONB for autosave
- Alternatives: Full replace on PATCH (rejected — draft changesets complex), single create-and-validate (rejected — poor UX)
- Consequences: `draft_data` blob as intermediate state; publish atomically validates + materializes; old `base_sets/reps/duration` columns removed

- [ ] **Commit ADR**

```bash
git add docs/adr/
git commit -m "docs(adr): document workout canvas architecture decisions"
```

- [ ] **Final commit**

```bash
git add -p  # stage any remaining changes
git commit -m "feat: complete workout creation canvas UX — 3-panel layout, draft/publish flow"
```
