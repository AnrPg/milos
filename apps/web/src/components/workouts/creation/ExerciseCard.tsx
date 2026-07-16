"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { FORMAT_EXERCISE_CONTEXT, type DraftExercise, type DraftSection, type LoadMode, type PrescriptionUnit } from "@/types/workout";

import { AdvancedSettingsPanel } from "./AdvancedSettingsPanel";
import { NumberStepper } from "./NumberStepper";
import { UnitCycler } from "./UnitCycler";
import { VariationsPanel } from "./VariationsPanel";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm", "bw"];
const LOAD_LABELS: Record<LoadMode, string> = { absolute: "kg", pct_1rm: "%RM", bw: "BW" };

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  scaleLevels: ScaleLevel[];
  sectionOptions: Array<{ id: string; name: string }>;
};

export function ExerciseCard({ exercise, section, scaleLevels, sectionOptions }: Props) {
  const i18n = useUiTranslations();
  const { updateExercise, toggleVariationsPanel, toggleAdvancedPanel } = useWorkoutCreationStore();
  const [noteOpen, setNoteOpen] = useState(() => Boolean(exercise.note));
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: exercise.localId,
    data: { type: "exercise", sectionId: section.localId },
  });

  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];

  // Compute the max secs cap for prescription when format has a fixed work interval.
  // Computed unconditionally so unit-switch logic can clamp on the same render.
  const secsCap: number | null = (() => {
    const p = section.formatParams;
    switch (section.format) {
      case "tabata":
      case "custom_hiit":
      case "billat":
        return (p.work_seconds as number) || null;
      case "emom":
        return (p.interval_seconds as number) || null;
      case "complex_emom": {
        const perMin = exercise.intervalAssignment !== null
          ? (p["interval_seconds_" + (exercise.intervalAssignment)] as number) || null
          : null;
        return perMin ?? ((p.interval_seconds as number) || null);
      }
      case "even_odd":
        return 60;
      default:
        return null;
    }
  })();
  const intervalCap = exercise.prescriptionUnit === "secs" ? secsCap : null;

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  function update(patch: Partial<DraftExercise>) {
    updateExercise(section.localId, exercise.localId, patch);
  }

  // ── Interval assignment badge ─────────────────────────────────────────────

  function renderIntervalBadge() {
    if (ctx.intervalMode === "odd_even") {
      const label =
        exercise.intervalAssignment === 1 ? i18n("odddc28f5f") :
        exercise.intervalAssignment === 2 ? i18n("even9e767ad") : i18n("both1f46983");
      const color =
        exercise.intervalAssignment === 1 ? "var(--accent)" :
        exercise.intervalAssignment === 2 ? "var(--lime)" : "var(--dim)";

      return (
        <button
          type="button"
          onClick={() => {
            const next =
              exercise.intervalAssignment === null ? 1 :
              exercise.intervalAssignment === 1 ? 2 : null;
            update({ intervalAssignment: next });
          }}
          className="shrink-0 rounded-lg px-2 py-0.5 text-xs font-bold"
          style={{ border: `1px solid ${color}`, color }}
          title={i18n("clickToCycleBothOddEvene64f8b1")}
        >
          {label}
        </button>
      );
    }

    if (ctx.intervalMode === "minute") {
      return (
        <div className="flex shrink-0 items-center gap-0.5">
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("min7eb0cee")}
          </span>
          <input
            type="number"
            value={exercise.intervalAssignment ?? ""}
            onChange={(event) =>
              update({ intervalAssignment: Number.parseInt(event.target.value, 10) || null })
            }
            placeholder="?"
            className="w-8 rounded bg-transparent text-center text-sm font-bold outline-none"
            style={{
              color: exercise.intervalAssignment ? "var(--accent)" : "var(--dim)",
              border: `1px solid ${exercise.intervalAssignment ? "var(--accent)" : "var(--dim)"}`,
              padding: "1px 4px",
            }}
            min={1}
          />
        </div>
      );
    }

    return null;
  }

  // ── Prescription field ────────────────────────────────────────────────────

  function renderPrescription() {
    if (!ctx.showPrescription) {
      if (section.format === "train_to_exhaustion") {
        return <span className="shrink-0 text-xs italic" style={{ color: "var(--dim)" }}>{i18n("toFailure1632d91")}</span>;
      }
      return null;
    }

    if (ctx.ladderPrescription) {
      const isPyramid = section.format === "pyramid";
      const isDescending = section.format === "ladder_descending";
      const stepSign = isPyramid ? "±" : isDescending ? "−" : "+";
      return (
        <div className="flex shrink-0 items-center gap-1">
          <span className="text-xs" style={{ color: "var(--dim)" }}>{isPyramid ? "peak" : "start"}</span>
          <NumberStepper
            value={exercise.prescriptionValue}
            onChange={(value) => update({ prescriptionValue: value })}
            min={1}
          />
          <UnitCycler
            options={PRESCRIPTION_UNITS}
            value={exercise.prescriptionUnit}
            onChange={(unit) => update({ prescriptionUnit: unit })}
          />
          <span className="text-xs font-bold" style={{ color: "var(--dim)" }}>{stepSign}</span>
          <NumberStepper
            value={exercise.prescriptionStep ?? 1}
            onChange={(value) => update({ prescriptionStep: value })}
            min={1}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>{i18n("round36fd5b1")}</span>
        </div>
      );
    }

    if (ctx.prescriptionHint) {
      return (
        <div className="flex shrink-0 items-center gap-1">
          <UnitCycler
            options={PRESCRIPTION_UNITS}
            value={exercise.prescriptionUnit}
            onChange={(unit) => update({ prescriptionUnit: unit })}
          />
          <span className="text-xs italic" style={{ color: "var(--dim)" }}>
            {ctx.prescriptionHint}
          </span>
        </div>
      );
    }

    return (
      <div className="flex shrink-0 items-center gap-1">
        <NumberStepper
          value={exercise.prescriptionValue}
          onChange={(value) => update({ prescriptionValue: value })}
          min={1}
          max={intervalCap ?? undefined}
        />
        <UnitCycler
          options={PRESCRIPTION_UNITS}
          value={exercise.prescriptionUnit}
          onChange={(unit) => {
            const patch: Partial<DraftExercise> = { prescriptionUnit: unit };
            if (unit === "secs" && secsCap !== null && exercise.prescriptionValue > secsCap) {
              patch.prescriptionValue = secsCap;
            }
            update(patch);
          }}
        />
        {ctx.prescriptionSuffix ? (
          <span className="text-xs italic" style={{ color: "var(--dim)" }}>
            {ctx.prescriptionSuffix}
          </span>
        ) : null}
      </div>
    );
  }

  // ── Clusters per set (cluster format only) ────────────────────────────────

  function renderClusters() {
    if (!ctx.showClusters) return null;
    return (
      <div className="flex shrink-0 items-center gap-1">
        <NumberStepper
          value={exercise.clustersPerSet ?? 5}
          onChange={(value) => update({ clustersPerSet: value })}
          min={1}
        />
        <span className="text-xs" style={{ color: "var(--muted)" }}>{i18n("clustersbc84c52")}</span>
      </div>
    );
  }

  // ── Load field ────────────────────────────────────────────────────────────

  function renderLoad() {
    if (!ctx.showLoad) return null;

    if (exercise.loadProgression) {
      return (
        <div className="flex shrink-0 items-center gap-1">
          <span
            className="rounded-lg px-2 py-0.5 text-xs font-semibold"
            style={{
              background: "color-mix(in srgb, var(--accent) 18%, transparent)",
              border: "1px solid var(--accent)",
              color: "var(--accent)",
            }}
          >
            {i18n("prog095e542")}
          </span>
          {/* still allow switching load type */}
          <UnitCycler
            options={LOAD_MODES}
            value={exercise.loadProgression.startMode}
            onChange={(mode) =>
              update({ loadProgression: { ...exercise.loadProgression!, startMode: mode } })
            }
            labels={LOAD_LABELS}
          />
        </div>
      );
    }

    if (exercise.loadMode === "bw") {
      return (
        <UnitCycler
          options={LOAD_MODES}
          value={exercise.loadMode}
          onChange={(mode) => update({ loadMode: mode, loadValue: null })}
          labels={LOAD_LABELS}
        />
      );
    }

    return (
      <div className="flex shrink-0 items-center gap-1">
        <input
          type="number"
          value={exercise.loadValue ?? ""}
          onChange={(event) => update({ loadValue: Number.parseInt(event.target.value, 10) || null })}
          placeholder="—"
          className="w-10 bg-transparent text-center text-sm font-semibold outline-none"
          style={{ color: "var(--text)" }}
          min={1}
        />
        <UnitCycler
          options={LOAD_MODES}
          value={exercise.loadMode}
          onChange={(mode) => update({ loadMode: mode, loadValue: mode === "bw" ? null : exercise.loadValue })}
          labels={LOAD_LABELS}
        />
      </div>
    );
  }

  // ── Progressive load panel ────────────────────────────────────────────────

  function renderProgressiveLoadPanel() {
    if (!ctx.showLoad || !exercise.loadProgression || exercise.loadMode === "bw") return null;
    const prog = exercise.loadProgression;

    return (
      <div className="border-t px-4 py-3" style={{ borderColor: "var(--dim)" }}>
        <div className="flex flex-wrap items-center gap-3">
          <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            {i18n("loadProgression1c3f8ed")}
          </span>
          <button
            type="button"
            onClick={() =>
              update({
                loadProgression: {
                  ...prog,
                  mode: prog.mode === "linear" ? "per_set" : "linear",
                  perSetValues: [],
                },
              })
            }
            className="rounded-lg px-2 py-0.5 text-xs font-semibold"
            style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--muted)" }}
          >
            {prog.mode === "linear" ? i18n("linearaf502f2") : i18n("perSet1e0dfe5")} ⟳
          </button>

          {prog.mode === "linear" ? (
            <>
              <div className="flex items-center gap-1">
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  {i18n("start952f375")}
                </span>
                <NumberStepper
                  value={prog.startValue}
                  onChange={(value) => update({ loadProgression: { ...prog, startValue: value } })}
                  min={1}
                />
                <UnitCycler
                  options={LOAD_MODES}
                  value={prog.startMode}
                  onChange={(mode) => update({ loadProgression: { ...prog, startMode: mode } })}
                  labels={LOAD_LABELS}
                />
              </div>
              <div className="flex items-center gap-1">
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  +
                </span>
                <NumberStepper
                  value={prog.stepValue}
                  onChange={(value) => update({ loadProgression: { ...prog, stepValue: value } })}
                  min={0}
                />
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  {i18n("set71c16be")}
                </span>
              </div>
            </>
          ) : (
            <div className="flex flex-wrap items-center gap-2">
              {Array.from({ length: exercise.sets }, (_, i) => (
                <div key={i} className="flex items-center gap-0.5">
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {i18n("s02aa629")}{i + 1}
                  </span>
                  <NumberStepper
                    value={prog.perSetValues[i] ?? prog.startValue}
                    onChange={(value) => {
                      const next = [...prog.perSetValues];
                      while (next.length <= i) next.push(prog.startValue);
                      next[i] = value;
                      update({ loadProgression: { ...prog, perSetValues: next } });
                    }}
                    min={0}
                  />
                </div>
              ))}
              <UnitCycler
                options={LOAD_MODES}
                value={prog.startMode}
                onChange={(mode) => update({ loadProgression: { ...prog, startMode: mode } })}
                labels={LOAD_LABELS}
              />
            </div>
          )}

          <button
            type="button"
            onClick={() => update({ loadProgression: null })}
            className="ml-auto text-xs"
            style={{ color: "var(--dim)" }}
          >
            {i18n("removee963907")}
          </button>
        </div>
      </div>
    );
  }

  // ── Render ────────────────────────────────────────────────────────────────

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
          <span
            {...attributes}
            {...listeners}
            className="shrink-0 cursor-grab text-base"
            style={{ color: "var(--dim)" }}
          >
            ⠿
          </span>

          {renderIntervalBadge()}

          <input
            type="text"
            value={exercise.name}
            onChange={(event) => update({ name: event.target.value })}
            placeholder={i18n("exerciseName9a5c1af")}
            className="min-w-[10rem] flex-1 bg-transparent text-base font-bold outline-none"
            style={{ color: "var(--text)" }}
          />

          {ctx.showSets ? (
            <div className="flex shrink-0 items-center gap-1">
              <NumberStepper
                value={exercise.sets}
                onChange={(value) => update({ sets: value })}
                min={1}
              />
              <span className="text-sm" style={{ color: "var(--muted)" }}>
                {i18n("setsd6c8220")}
              </span>
            </div>
          ) : null}

          {renderClusters()}
          {renderPrescription()}
          {renderLoad()}

          {/* Progressive load toggle — hidden only when BW (no numeric load to progress) */}
          {ctx.showLoad && exercise.loadMode !== "bw" && !exercise.loadProgression ? (
            <button
              type="button"
              onClick={() =>
                update({
                  loadProgression: {
                    mode: "linear",
                    startValue: exercise.loadValue ?? 40,
                    startMode: exercise.loadMode,
                    stepValue: 10,
                    perSetValues: [],
                  },
                  loadValue: null,
                })
              }
              className="shrink-0 text-xs"
              style={{ color: "var(--dim)" }}
              title={i18n("setProgressiveLoadAcrossSetsb3a6402")}
            >
              ∿
            </button>
          ) : null}

          <button
            type="button"
            onClick={() => toggleVariationsPanel(section.localId, exercise.localId)}
            className="shrink-0 rounded-xl px-2 py-1 text-xs font-semibold transition-colors"
            style={{
              background: exercise.variationsOpen
                ? "color-mix(in srgb, var(--accent) 20%, transparent)"
                : "var(--bg)",
              border: "1px solid var(--dim)",
              color: exercise.variationsOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            {i18n("varsb9069e3")} {exercise.variationsOpen ? "▲" : "▾"}
          </button>

          <button
            type="button"
            onClick={() => {
              const next = !noteOpen;
              setNoteOpen(next);
              if (!next) update({ note: null });
            }}
            className="shrink-0 rounded-xl px-2 py-1 text-xs font-semibold transition-colors"
            style={{
              background: noteOpen ? "color-mix(in srgb, var(--info) 20%, transparent)" : "var(--bg)",
              border: `1px solid ${noteOpen ? "var(--info)" : "var(--dim)"}`,
              color: noteOpen ? "var(--info)" : "var(--muted)",
            }}
            title={i18n("coachNoteForThisExerciseb05bf2d")}
          >
            📝
          </button>

          <button
            type="button"
            onClick={() => toggleAdvancedPanel(section.localId, exercise.localId)}
            className="shrink-0 rounded-xl px-2 py-1 text-xs font-semibold transition-colors"
            style={{
              background: exercise.advancedOpen
                ? "color-mix(in srgb, var(--accent) 20%, transparent)"
                : "var(--bg)",
              border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
              color: exercise.advancedOpen ? "var(--accent)" : "var(--muted)",
            }}
          >
            ⋯
          </button>
        </div>

        {renderProgressiveLoadPanel()}

        {noteOpen ? (
          <div className="border-t px-4 py-2" style={{ borderColor: "var(--dim)" }}>
            <textarea
              rows={2}
              placeholder={i18n("coachNoteForThisExercisecab745f")}
              className="w-full resize-none bg-transparent text-xs outline-none"
              style={{ color: "var(--text)" }}
              value={exercise.note ?? ""}
              onChange={(e) => update({ note: e.target.value || null })}
            />
          </div>
        ) : null}

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
