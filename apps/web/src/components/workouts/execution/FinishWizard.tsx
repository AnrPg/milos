"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useState } from "react";
import type { TimerSegment } from "@/api/executions";
import type { ExerciseModification } from "@/api/executions";
import { SemanticLabel } from "@/components/semantic-label";
import { LocalizedScore } from "@/components/localized-score";
import { semanticLabel } from "@/i18n/presentation";

type SectionScore = {
  section_id: string;
  section_name?: string | null;
  value: number | string;
  unit?: string;
  score_type?: string;
  source?: string;
  kind?: string;
};

// ── Step 1: Score entry ───────────────────────────────────────────────────────

function ScoreEntryStep({
  scores,
  segments,
  onBack,
  onNext,
  onSkip,
}: {
  scores: SectionScore[];
  segments: TimerSegment[];
  onBack: (() => void) | null;
  onNext: (edited: SectionScore[]) => void;
  onSkip: () => void;
}) {
  const i18n = useUiTranslations();
  const scoreableSections = React.useMemo(() => {
    const seen = new Set<string>();
    const result: Array<{
      section_id: string;
      section_name: string;
      unit: string;
      score_type: string;
    }> = [];
    for (const seg of segments) {
      if (!seg.scoreable || !seg.score_config) continue;
      if (seen.has(seg.section_id)) continue;
      seen.add(seg.section_id);
      result.push({
        section_id: seg.section_id,
        section_name: seg.section_name,
        unit: seg.score_config.unit ?? "",
        score_type: seg.score_config.type ?? "",
      });
    }
    return result;
  }, [segments]);

  const [editedScores, setEditedScores] = useState<Record<string, string>>(() => {
    const init: Record<string, string> = {};
    for (const sec of scoreableSections) {
      const existing = scores.find((s) => s.section_id === sec.section_id);
      init[sec.section_id] = existing ? String(existing.value) : "";
    }
    return init;
  });

  function buildResult(): SectionScore[] {
    const shownIds = new Set(scoreableSections.map((s) => s.section_id));
    const passthrough = scores.filter((s) => !shownIds.has(s.section_id));
    const entered = scoreableSections
      .filter((sec) => editedScores[sec.section_id] !== "")
      .map((sec) => {
        const raw = editedScores[sec.section_id] ?? "";
        const numVal = Number(raw);
        return {
          section_id: sec.section_id,
          section_name: sec.section_name,
          value: isNaN(numVal) ? raw : numVal,
          unit: sec.unit || undefined,
          score_type: sec.score_type || undefined,
          source: "user",
          kind: "final",
        };
      });
    return [...passthrough, ...entered];
  }

  if (scoreableSections.length === 0) {
    return (
      <div
        className="flex h-screen flex-col items-center justify-center gap-6 p-8"
        style={{ background: "var(--bg)" }}
      >
        <div className="text-5xl">🏁</div>
        <p className="text-xl font-bold text-center" style={{ color: "var(--text)" }}>
          {i18n("noScoredSections03f16d5")}
        </p>
        <p className="text-sm text-center max-w-xs" style={{ color: "var(--muted)" }}>
          {i18n("thisWorkoutHasNoSectionsThatTrackAad42c8f")}
        </p>
        <button
          type="button"
          onClick={() => onNext(scores)}
          className="w-full max-w-xs rounded-2xl py-3.5 text-base font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
        >
          {i18n("next2f04eb1")}
        </button>
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <div className="flex items-center justify-between px-5 pt-8 pb-2">
        <div>
          {onBack && (
            <button type="button" onClick={onBack} className="text-sm" style={{ color: "var(--dim)" }}>
              {i18n("backc32ae9f")}
            </button>
          )}
        </div>
        <button type="button" onClick={onSkip} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {i18n("skip10b7bbe")}
        </button>
      </div>

      <div className="flex flex-col items-center gap-2 pt-4 pb-6 px-6">
        <div className="text-4xl">🏁</div>
        <h2 className="text-xl font-bold text-center">{i18n("logYourScoresaeffd3b")}</h2>
        <p className="text-sm text-center max-w-xs" style={{ color: "var(--muted)" }}>
          {i18n("enterYourResultForEachScoredSectionPrefb25b9b")}
        </p>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-3">
        {scoreableSections.map((sec) => (
          <div
            key={sec.section_id}
            className="rounded-2xl p-4"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <div className="flex items-center justify-between gap-4">
              <div className="min-w-0">
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {sec.section_name}
                </p>
                {sec.score_type && (
                  <p
                    className="text-[10px] uppercase tracking-[0.16em] mt-0.5"
                    style={{ color: "var(--dim)" }}
                  >
                    <SemanticLabel value={sec.score_type} />
                  </p>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-1.5">
                <input
                  type="number"
                  inputMode="decimal"
                  className="w-24 rounded-xl px-3 py-2 text-end text-sm font-bold outline-none"
                  style={{
                    background: "var(--bg)",
                    border: `1px solid ${editedScores[sec.section_id] ? "var(--primary)" : "var(--border)"}`,
                    color: "var(--text)",
                  }}
                  value={editedScores[sec.section_id] ?? ""}
                  placeholder="—"
                  onChange={(e) =>
                    setEditedScores((prev) => ({ ...prev, [sec.section_id]: e.target.value }))
                  }
                />
                {sec.unit && (
                  <span className="text-xs shrink-0" style={{ color: "var(--muted)" }}>
                    <SemanticLabel value={sec.unit} />
                  </span>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="p-4 pt-0">
        <button
          type="button"
          onClick={() => onNext(buildResult())}
          className="w-full rounded-2xl py-3.5 text-base font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
        >
          {i18n("next2f04eb1")}
        </button>
      </div>
    </div>
  );
}

// ── Step 2: Actual-workout patch editor ───────────────────────────────────────

type EditableField = {
  field: string;
  label: string;
  canonicalValue: string | number | boolean;
  unit?: string | null;
  inputMode?: "numeric" | "decimal" | "text";
};

type ExpandedWorkoutRow = {
  rowKey: string;
  rowIndex: number;
  sectionId: string;
  sectionName: string;
  segmentKey: string;
  roundIndex: number | null;
  setIndex: number | null;
  exerciseId: string;
  exerciseName: string;
  fields: EditableField[];
};

function modificationKey(row: ExpandedWorkoutRow, field: string) {
  return [row.segmentKey, row.exerciseId, row.setIndex ?? 0, row.roundIndex ?? 0, field].join(":");
}

function fieldType(field: string): ExerciseModification["type"] {
  if (field === "load") return "weight_changed";
  if (field === "reps" || field === "prescription_value") return "reps_changed";
  if (field === "sets") return "sets_changed";
  if (field === "duration_seconds") return "time_changed";
  if (field === "exercise_name") return "exercise_substituted";
  if (field === "skipped") return "skipped";
  return "field_changed";
}

function parseActualValue(value: string, canonical: string | number | boolean) {
  if (typeof canonical === "number") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : value;
  }

  if (typeof canonical === "boolean") {
    return value === "true";
  }

  return value;
}

function buildExpandedRows(segments: TimerSegment[], i18n: ReturnType<typeof useUiTranslations>) {
  const rows: ExpandedWorkoutRow[] = [];
  let rowIndex = 1;

  for (const segment of segments) {
    for (const exercise of segment.exercises ?? []) {
      if (exercise.excluded) continue;

      const setCount = Math.max(1, exercise.sets ?? 1);

      for (let setIndex = 1; setIndex <= setCount; setIndex += 1) {
        const fields: EditableField[] = [
          {
            field: "exercise_name",
            label: i18n("exercise1091b7f"),
            canonicalValue: exercise.name,
            inputMode: "text",
          },
        ];

        if (exercise.prescription_value != null) {
          fields.push({
            field: "reps",
            label: semanticLabel(exercise.prescription_unit ?? "reps", i18n),
            canonicalValue: exercise.prescription_value,
            unit: exercise.prescription_unit ?? "reps",
            inputMode: "decimal",
          });
        }

        if (exercise.load_value != null) {
          fields.push({
            field: "load",
            label: exercise.load_mode === "pct_1rm" ? i18n("percentOneRepMaxUnit") : i18n("kilogramsUnit"),
            canonicalValue: exercise.load_value,
            unit: exercise.load_mode === "pct_1rm" ? "%" : "kg",
            inputMode: "decimal",
          });
        }

        rows.push({
          rowKey: `${segment.segment_key}:${exercise.id}:${setIndex}`,
          rowIndex,
          sectionId: segment.section_id,
          sectionName: segment.section_name,
          segmentKey: segment.segment_key,
          roundIndex: segment.round ?? null,
          setIndex,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          fields,
        });
        rowIndex += 1;
      }
    }
  }

  return rows;
}

function patchFromEdit(
  row: ExpandedWorkoutRow,
  field: EditableField,
  rawActualValue: string,
): ExerciseModification | null {
  const actualValue = parseActualValue(rawActualValue, field.canonicalValue);
  if (String(actualValue) === String(field.canonicalValue)) return null;

  return {
    patch_id: modificationKey(row, field.field),
    type: fieldType(field.field),
    field: field.field,
    section_id: row.sectionId,
    section_name: row.sectionName,
    segment_key: row.segmentKey,
    exercise_id: row.exerciseId,
    exercise_name: row.exerciseName,
    set_index: row.setIndex,
    round_index: row.roundIndex,
    row_index: row.rowIndex,
    canonical_value: field.canonicalValue,
    actual_value: actualValue,
    unit: field.unit ?? null,
  };
}

function ModificationsEditorStep({
  segments,
  initialMods,
  onBack,
  onNext,
  onSkip,
}: {
  segments: TimerSegment[];
  initialMods: ExerciseModification[];
  onBack: () => void;
  onNext: (mods: ExerciseModification[]) => void;
  onSkip: () => void;
}) {
  const i18n = useUiTranslations();
  const rows = React.useMemo(() => buildExpandedRows(segments, i18n), [segments, i18n]);
  const sections = React.useMemo(() => {
    const grouped = new Map<string, ExpandedWorkoutRow[]>();
    for (const row of rows) {
      grouped.set(row.sectionId, [...(grouped.get(row.sectionId) ?? []), row]);
    }
    return Array.from(grouped.entries()).map(([sectionId, sectionRows]) => ({
      sectionId,
      sectionName: sectionRows[0]?.sectionName ?? sectionId,
      rows: sectionRows,
    }));
  }, [rows]);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(sections.map((section) => [section.sectionId, true])),
  );
  const [modsByKey, setModsByKey] = useState<Record<string, ExerciseModification>>(() =>
    Object.fromEntries(initialMods.map((mod) => [mod.patch_id ?? `${mod.segment_key}:${mod.exercise_id}:${mod.field}`, mod])),
  );
  const [editing, setEditing] = useState<{
    key: string;
    row: ExpandedWorkoutRow;
    field: EditableField;
    value: string;
  } | null>(null);

  function commitEdit() {
    if (!editing) return;
    const nextPatch = patchFromEdit(editing.row, editing.field, editing.value);
    setModsByKey((prev) => {
      const next = { ...prev };
      if (nextPatch) {
        next[editing.key] = nextPatch;
      } else {
        delete next[editing.key];
      }
      return next;
    });
    setEditing(null);
  }

  function skipRow(row: ExpandedWorkoutRow) {
    const patch: ExerciseModification = {
      patch_id: modificationKey(row, "skipped"),
      type: "skipped",
      field: "skipped",
      section_id: row.sectionId,
      section_name: row.sectionName,
      segment_key: row.segmentKey,
      exercise_id: row.exerciseId,
      exercise_name: row.exerciseName,
      set_index: row.setIndex,
      round_index: row.roundIndex,
      row_index: row.rowIndex,
      canonical_value: false,
      actual_value: true,
    };
    setModsByKey((prev) => ({ ...prev, [patch.patch_id!]: patch }));
  }

  function displayValue(row: ExpandedWorkoutRow, field: EditableField) {
    const key = modificationKey(row, field.field);
    return modsByKey[key]?.actual_value ?? field.canonicalValue;
  }

  function currentModifications() {
    if (!editing) return Object.values(modsByKey);

    const next = { ...modsByKey };
    const finalPatch = patchFromEdit(editing.row, editing.field, editing.value);

    if (finalPatch) {
      next[editing.key] = finalPatch;
    } else {
      delete next[editing.key];
    }

    return Object.values(next);
  }

  return (
    <div className="flex h-screen flex-col" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <div className="flex items-center justify-between px-5 pt-8 pb-2">
        <button type="button" onClick={onBack} className="text-sm" style={{ color: "var(--dim)" }}>
          {i18n("backc32ae9f")}
        </button>
        <button type="button" onClick={onSkip} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {i18n("skip10b7bbe")}
        </button>
      </div>

      <div className="flex flex-col items-center gap-2 pt-4 pb-6 px-6">
        <h2 className="text-xl font-bold text-center">{i18n("anyModifications97c3e24")}</h2>
        <p className="text-sm text-center max-w-xs" style={{ color: "var(--muted)" }}>
          {i18n("tapAnyPrescribedValueAndTypeWhatYouActuallyDidbb2b6a9")}
        </p>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-3">
        {sections.map((section) => {
          const expanded = expandedSections[section.sectionId] ?? true;
          const sectionModCount = Object.values(modsByKey).filter((mod) => mod.section_id === section.sectionId).length;

          return (
            <section
              key={section.sectionId}
              className="overflow-hidden rounded-2xl"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <button
                type="button"
                className="flex w-full items-center justify-between gap-3 px-4 py-3 text-start"
                onClick={() => setExpandedSections((prev) => ({ ...prev, [section.sectionId]: !expanded }))}
              >
                <span className="min-w-0 truncate text-sm font-bold" style={{ color: "var(--text)" }}>
                  {section.sectionName}
                </span>
                <span className="shrink-0 text-xs font-semibold" style={{ color: sectionModCount ? "var(--warning)" : "var(--dim)" }}>
                  {sectionModCount ? `${sectionModCount} ${i18n("modified19a532c")}` : expanded ? "−" : "+"}
                </span>
              </button>

              {expanded ? (
                <div className="divide-y" style={{ borderColor: "var(--border)" }}>
                  {section.rows.map((row) => {
                    const skipped = Boolean(modsByKey[modificationKey(row, "skipped")]);

                    return (
                      <div key={row.rowKey} className="px-4 py-3">
                        <div className="mb-2 flex items-center justify-between gap-3">
                          <p className="min-w-0 truncate text-sm font-semibold" style={{ color: skipped ? "var(--danger, var(--primary))" : "var(--text)" }}>
                            {row.setIndex ? `${i18n("setLabel")} ${row.setIndex} · ` : ""}
                            {row.exerciseName}
                          </p>
                          <button
                            type="button"
                            className="shrink-0 rounded-lg px-2.5 py-1 text-xs font-semibold"
                            style={{
                              background: skipped ? "color-mix(in srgb, var(--danger, var(--primary)) 14%, transparent)" : "var(--panel-muted)",
                              color: skipped ? "var(--danger, var(--primary))" : "var(--dim)",
                              border: "1px solid var(--border)",
                            }}
                            onClick={() => {
                              if (skipped) {
                                setModsByKey((prev) => {
                                  const next = { ...prev };
                                  delete next[modificationKey(row, "skipped")];
                                  return next;
                                });
                              } else {
                                skipRow(row);
                              }
                            }}
                          >
                            {skipped ? i18n("undoSkip7bc61ef") : i18n("skipped5a000ad")}
                          </button>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {row.fields.map((field) => {
                            const key = modificationKey(row, field.field);
                            const changed = Boolean(modsByKey[key]);
                            const value = displayValue(row, field);
                            const isEditing = editing?.key === key;

                            return (
                              <div key={field.field} className="min-w-[5.5rem]">
                                <p className="mb-1 text-[10px] font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                                  {field.label}
                                </p>
                                {isEditing ? (
                                  <input
                                    autoFocus
                                    className="w-full rounded-xl px-3 py-2 text-sm font-bold outline-none"
                                    inputMode={field.inputMode === "text" ? "text" : field.inputMode}
                                    style={{
                                      background: "var(--bg)",
                                      border: "1px solid var(--primary)",
                                      color: "var(--text)",
                                    }}
                                    value={editing.value}
                                    onChange={(event) => setEditing((prev) => prev ? { ...prev, value: event.target.value } : prev)}
                                    onBlur={commitEdit}
                                    onKeyDown={(event) => {
                                      if (event.key === "Enter") commitEdit();
                                      if (event.key === "Escape") setEditing(null);
                                    }}
                                  />
                                ) : (
                                  <button
                                    type="button"
                                    className="w-full rounded-xl px-3 py-2 text-start text-sm font-bold"
                                    style={{
                                      background: changed ? "color-mix(in srgb, var(--warning) 14%, transparent)" : "var(--panel-muted)",
                                      border: `1px solid ${changed ? "var(--warning)" : "var(--border)"}`,
                                      color: changed ? "var(--warning)" : "var(--text)",
                                    }}
                                    onClick={() => setEditing({ key, row, field, value: String(value) })}
                                  >
                                    {String(value)}
                                    {field.unit ? <span className="ms-1 text-xs font-medium">{semanticLabel(field.unit, i18n)}</span> : null}
                                  </button>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : null}
            </section>
          );
        })}
      </div>

      <div className="p-4 pt-0">
        <button
          type="button"
          onClick={() => {
            onNext(currentModifications());
          }}
          className="w-full rounded-2xl py-3.5 text-base font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
        >
          {i18n("next2f04eb1")}
        </button>
      </div>
    </div>
  );
}

// ── Step 3: Confirm ───────────────────────────────────────────────────────────

function ConfirmStep({
  scores,
  modifications,
  segments,
  isSaving,
  feedback,
  onBack,
  onSave,
}: {
  scores: SectionScore[];
  modifications: ExerciseModification[];
  segments: TimerSegment[];
  isSaving: boolean;
  feedback: string | null;
  onBack: () => void;
  onSave: () => void;
}) {
  const i18n = useUiTranslations();
  const exerciseMap = React.useMemo(() => {
    const map: Record<string, string> = {};
    for (const seg of segments) {
      for (const ex of seg.exercises ?? []) {
        map[ex.id] = ex.name;
      }
    }
    return map;
  }, [segments]);

  return (
    <div
      className="flex h-screen flex-col"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <div className="flex items-center px-5 pt-8 pb-2">
        <button type="button" onClick={onBack} className="text-sm" style={{ color: "var(--dim)" }}>
          {i18n("backc32ae9f")}
        </button>
      </div>

      <div className="flex flex-col items-center gap-2 pt-4 pb-6 px-6">
        <div className="text-5xl">🏆</div>
        <div className="text-2xl font-bold text-center" style={{ color: "var(--text)" }}>
          {i18n("readyToSave3fab096")}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-4">
        {scores.length > 0 && (
          <div>
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em] mb-2 px-1"
              style={{ color: "var(--dim)" }}
            >
              {i18n("scores126cb93")}
            </p>
            <div className="space-y-2">
              {scores.map((score) => (
                <div
                  key={score.section_id}
                  className="flex justify-between items-center rounded-xl px-4 py-2.5"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                >
                  <span className="text-sm" style={{ color: "var(--muted)" }}>
                    {score.section_name ??
                      segments.find((s) => s.section_id === score.section_id)?.section_name ??
                      score.section_id}
                  </span>
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    <LocalizedScore value={score.value} scoreType={score.score_type} unit={score.unit} />
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {modifications.length > 0 && (
          <div>
            <p
              className="text-xs font-semibold uppercase tracking-[0.18em] mb-2 px-1"
              style={{ color: "var(--dim)" }}
            >
              {i18n("modifications405f450")}
            </p>
            <div className="space-y-2">
              {modifications.map((mod, i) => (
                <div
                  key={(mod.patch_id ?? mod.exercise_id ?? mod.section_id) + "-" + (i)}
                  className="flex justify-between items-center rounded-xl px-4 py-2.5"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                >
                  <span className="text-sm truncate" style={{ color: "var(--muted)" }}>
                    {mod.exercise_name ??
                      (mod.exercise_id ? exerciseMap[mod.exercise_id] : null) ??
                      mod.section_name ??
                      mod.section_id}
                  </span>
                  <span
                    className="text-xs font-semibold shrink-0 ms-2"
                    style={{
                      color:
                        mod.type === "skipped"
                          ? "var(--danger, var(--primary))"
                          : "var(--warning)",
                    }}
                  >
                    {mod.type === "skipped"
                      ? i18n("skipped5a000ad")
                      : `${mod.field}: ${String(mod.actual_value)}`}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {scores.length === 0 && modifications.length === 0 && (
          <p className="text-center text-sm py-8" style={{ color: "var(--dim)" }}>
            {i18n("noScoresOrModificationsLogged685c678")}
          </p>
        )}
      </div>

      {feedback && (
        <p className="text-sm text-center px-4" style={{ color: "var(--danger, var(--primary))" }}>
          {feedback}
        </p>
      )}

      <div className="p-4 pt-2">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="w-full rounded-2xl py-3.5 text-base font-semibold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast, #fff)" }}
        >
          {isSaving ? i18n("saving56a2285") : i18n("saveDone3614269")}
        </button>
      </div>
    </div>
  );
}

// ── Public component ──────────────────────────────────────────────────────────

export function FinishWizard({
  scores,
  segments,
  initialModifications,
  isSaving,
  feedback,
  onConfirm,
}: {
  scores: SectionScore[];
  segments: TimerSegment[];
  initialModifications: ExerciseModification[];
  isSaving: boolean;
  feedback: string | null;
  onConfirm: (editedScores: SectionScore[], modifications: ExerciseModification[]) => void;
}) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [confirmedScores, setConfirmedScores] = useState<SectionScore[]>(scores);
  const [confirmedMods, setConfirmedMods] = useState<ExerciseModification[]>(initialModifications);

  function handleScoresNext(edited: SectionScore[]) {
    setConfirmedScores(edited);
    setStep(2);
  }

  function handleModsNext(mods: ExerciseModification[]) {
    setConfirmedMods(mods);
    setStep(3);
  }

  function handleSave() {
    onConfirm(confirmedScores, confirmedMods);
  }

  if (step === 1) {
    return (
      <ScoreEntryStep
        scores={scores}
        segments={segments}
        onBack={null}
        onNext={handleScoresNext}
        onSkip={() => setStep(2)}
      />
    );
  }

  if (step === 2) {
    return (
      <ModificationsEditorStep
        segments={segments}
        initialMods={confirmedMods}
        onBack={() => setStep(1)}
        onNext={handleModsNext}
        onSkip={() => setStep(3)}
      />
    );
  }

  return (
    <ConfirmStep
      scores={confirmedScores}
      modifications={confirmedMods}
      segments={segments}
      isSaving={isSaving}
      feedback={feedback}
      onBack={() => setStep(2)}
      onSave={handleSave}
    />
  );
}
