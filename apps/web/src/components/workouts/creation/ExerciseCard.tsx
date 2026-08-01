"use client";






import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { concreteSetPrescriptions, FORMAT_EXERCISE_CONTEXT, type DraftExercise, type DraftSection, type LoadMode, type PrescriptionUnit } from "@/types/workout";

import { AdvancedSettingsPanel } from "./AdvancedSettingsPanel";
import { NumberStepper } from "./NumberStepper";
import { UnitCycler } from "./UnitCycler";
import { VariationsPanel } from "./VariationsPanel";

const PRESCRIPTION_UNITS: PrescriptionUnit[] = ["reps", "secs", "kcal"];
const LOAD_MODES: LoadMode[] = ["absolute", "pct_1rm", "bw"];

type Props = {
  exercise: DraftExercise;
  section: DraftSection;
  scaleLevels: ScaleLevel[];
  sectionOptions: Array<{ id: string; name: string }>;
  selected?: boolean;
  onSelectedChange?: (selected: boolean) => void;
  grouped?: boolean;
  groupColor?: string;
};

export function ExerciseCard({ exercise, section, scaleLevels, sectionOptions, selected = false, onSelectedChange, grouped = false, groupColor }: Props) {
  const i18n = useUiTranslations();
  const LOAD_LABELS: Record<LoadMode, string> = { absolute: i18n("kilogramsUnit"), pct_1rm: i18n("percentOneRepMaxUnit"), bw: i18n("bw4d64743") };

  const { updateExercise, toggleVariationsPanel, toggleAdvancedPanel } = useWorkoutCreationStore();
  const [noteOpen, setNoteOpen] = useState(() => Boolean(exercise.note));
  const [detailsPinned, setDetailsPinned] = useState(false);
  const [detailsHovered, setDetailsHovered] = useState(false);
  const detailsOpen = detailsPinned || detailsHovered;
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
          <span className="text-xs" style={{ color: "var(--dim)" }}>{isPyramid ? i18n("peakLabel") : i18n("start952f375")}</span>
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
            {i18n(ctx.prescriptionHint)}
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
            {i18n(ctx.prescriptionSuffix)}
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

  function renderSetDetailsPanel() {
    if (!ctx.showSets) {
      return (
        <div
          className="flex flex-wrap items-center gap-3 border-t px-4 py-3"
          style={{ borderColor: "var(--dim)" }}
        >
          {renderClusters()}
          {renderPrescription()}
          {renderLoad()}
        </div>
      );
    }

    if (exercise.sets < 1) return null;
    const setRows = concreteSetPrescriptions(exercise);

    return (
      <div className="border-t px-4 py-3" style={{ borderColor: "var(--dim)" }}>
        <div className="mb-2 text-xs font-bold uppercase" style={{ color: "var(--muted)" }}>
          {i18n("setDetailsLabel")}
        </div>
        {ctx.showClusters ? <div className="mb-2">{renderClusters()}</div> : null}
        <div className="space-y-2">
          {setRows.map((setRow, index) => (
            <div
              className="grid items-center gap-2 sm:grid-cols-[auto_1fr_1fr_1fr]"
              key={setRow.setIndex}
            >
              <span className="text-xs font-bold" style={{ color: "var(--dim)" }}>
                {i18n("setNumberLabel", { number: setRow.setIndex })}
              </span>
              <div className="flex items-center gap-1">
                <NumberStepper
                  min={1}
                  onChange={(value) => {
                    const next = [...setRows];
                    next[index] = { ...setRow, prescriptionValue: value };
                    update({ setPrescriptions: next });
                  }}
                  value={setRow.prescriptionValue ?? exercise.prescriptionValue}
                />
                <UnitCycler
                  onChange={(value) => {
                    const next = [...setRows];
                    next[index] = { ...setRow, prescriptionUnit: value };
                    update({ setPrescriptions: next });
                  }}
                  options={PRESCRIPTION_UNITS}
                  value={setRow.prescriptionUnit ?? exercise.prescriptionUnit}
                />
              </div>
              <div className="flex items-center gap-1">
                <input
                  className="w-14 bg-transparent text-center text-sm outline-none"
                  min={0}
                  onChange={(event) => {
                    const next = [...setRows];
                    next[index] = {
                      ...setRow,
                      loadValue: event.target.value === "" ? null : Number(event.target.value),
                    };
                    update({ setPrescriptions: next });
                  }}
                  type="number"
                  value={setRow.loadValue ?? ""}
                />
                <UnitCycler
                  labels={LOAD_LABELS}
                  onChange={(value) => {
                    const next = [...setRows];
                    next[index] = { ...setRow, loadMode: value };
                    update({ setPrescriptions: next });
                  }}
                  options={LOAD_MODES}
                  value={setRow.loadMode ?? exercise.loadMode}
                />
              </div>
              <input
                className="min-w-0 bg-transparent text-xs outline-none"
                onChange={(event) => {
                  const next = [...setRows];
                  next[index] = { ...setRow, note: event.target.value || null };
                  update({ setPrescriptions: next });
                }}
                placeholder={i18n("setNotePlaceholder")}
                type="text"
                value={setRow.note ?? ""}
              />
            </div>
          ))}
        </div>
      </div>
    );
  }

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div ref={setNodeRef} style={{ ...style, overflow: "visible" }}>
      <div
        className="rounded-2xl"
        onMouseEnter={() => setDetailsHovered(true)}
        onMouseLeave={() => setDetailsHovered(false)}
        style={{
          background: "var(--card)",
          border: `1px solid ${exercise.advancedOpen ? "var(--accent)" : "var(--dim)"}`,
          boxShadow: groupColor ? `inset 3px 0 0 ${groupColor}` : "none",
        }}
      >
        <div className="flex flex-wrap items-center gap-3 px-4 py-3" onClick={() => setDetailsPinned((current) => !current)}>
          <input
            aria-label={i18n("selectExerciseForGrouping")}
            checked={selected}
            className="h-4 w-4 shrink-0"
            onChange={(event) => onSelectedChange?.(event.target.checked)}
            onClick={(event) => event.stopPropagation()}
            type="checkbox"
          />
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
            onClick={(event) => event.stopPropagation()}
            placeholder={i18n("exerciseName9a5c1af")}
            className="min-w-[10rem] flex-1 bg-transparent text-base font-bold outline-none"
            style={{ color: "var(--text)" }}
          />

          {ctx.showSets && !grouped && detailsOpen ? (
            <div className="flex shrink-0 items-center gap-1">
              <NumberStepper
                value={exercise.sets}
                onChange={(value) =>
                  update({
                    sets: value,
                    setPrescriptions: concreteSetPrescriptions({ ...exercise, sets: value }),
                  })
                }
                min={1}
              />
              <span className="text-sm" style={{ color: "var(--muted)" }}>
                {i18n("setsd6c8220")}
              </span>
            </div>
          ) : null}

          <button
            type="button"
            onClick={(event) => { event.stopPropagation(); toggleVariationsPanel(section.localId, exercise.localId); }}
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
            onClick={(event) => {
              event.stopPropagation();
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
            onClick={(event) => { event.stopPropagation(); toggleAdvancedPanel(section.localId, exercise.localId); }}
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

        {detailsOpen ? renderSetDetailsPanel() : null}

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
