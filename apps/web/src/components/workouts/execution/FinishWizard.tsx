"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useState } from "react";
import type { TimerSegment } from "@/api/executions";
import type { ExerciseModification } from "@/api/executions";

type SectionScore = {
  section_id: string;
  section_name?: string | null;
  value: number | string;
  unit?: string;
  score_type?: string;
  source?: string;
  kind?: string;
};

type ExerciseMeta = {
  id: string;
  name: string;
  sets?: number | null;
  prescription_value?: number | null;
  prescription_unit?: string | null;
  load_value?: number | null;
  load_mode?: string | null;
};

function collectExercises(segments: TimerSegment[]): ExerciseMeta[] {
  const seen = new Set<string>();
  const result: ExerciseMeta[] = [];
  for (const seg of segments) {
    for (const ex of seg.exercises ?? []) {
      if (!ex.excluded && !seen.has(ex.id)) {
        seen.add(ex.id);
        result.push(ex);
      }
    }
  }
  return result;
}

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
                    {sec.score_type.replace(/_/g, " ")}
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
                    {sec.unit}
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

// ── Step 2: Modifications editor (pre-seeded, fully editable) ─────────────────

type ModState = {
  active: boolean;
  skipped: boolean;
  actualSets: string;
  actualValue: string;
  actualLoad: string;
};

function buildInitialModState(
  exercises: ExerciseMeta[],
  initialMods: ExerciseModification[],
): Record<string, ModState> {
  const state: Record<string, ModState> = {};
  for (const ex of exercises) {
    const existing = initialMods.find((m) => m.exercise_id === ex.id);
    state[ex.id] = existing
      ? {
          active: true,
          skipped: existing.type === "skipped",
          actualSets: existing.sets != null ? String(existing.sets) : (ex.sets != null ? String(ex.sets) : ""),
          actualValue:
            existing.actual_value != null
              ? String(existing.actual_value)
              : ex.prescription_value != null
                ? String(ex.prescription_value)
                : "",
          actualLoad:
            ex.load_value != null ? String(ex.load_value) : "",
        }
      : {
          active: false,
          skipped: false,
          actualSets: ex.sets != null ? String(ex.sets) : "",
          actualValue: ex.prescription_value != null ? String(ex.prescription_value) : "",
          actualLoad: ex.load_value != null ? String(ex.load_value) : "",
        };
  }
  return state;
}

function buildModifications(
  exercises: ExerciseMeta[],
  modState: Record<string, ModState>,
): ExerciseModification[] {
  const result: ExerciseModification[] = [];
  for (const ex of exercises) {
    const s = modState[ex.id];
    if (!s?.active) continue;

    if (s.skipped) {
      result.push({
        exercise_id: ex.id,
        type: "skipped",
        prescribed_value: ex.prescription_value ?? null,
        actual_value: 0,
        prescribed_mins: null,
        actual_mins: null,
        sets: ex.sets ?? null,
      });
      continue;
    }

    const parsedActualValue = s.actualValue !== "" ? Number(s.actualValue) : null;
    const parsedActualLoad = s.actualLoad !== "" ? Number(s.actualLoad) : null;
    const parsedActualSets = s.actualSets !== "" ? Number(s.actualSets) : null;

    const loadChanged =
      ex.load_value != null &&
      parsedActualLoad !== null &&
      parsedActualLoad !== ex.load_value;
    const repsChanged =
      ex.prescription_value != null &&
      parsedActualValue !== null &&
      parsedActualValue !== ex.prescription_value;
    const type: ExerciseModification["type"] = loadChanged
      ? "weight_changed"
      : repsChanged
        ? "reps_changed"
        : "other";

    result.push({
      exercise_id: ex.id,
      type,
      prescribed_value: ex.prescription_value ?? null,
      actual_value: parsedActualValue,
      prescribed_mins: null,
      actual_mins: null,
      sets: parsedActualSets ?? ex.sets ?? null,
    });
  }
  return result;
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
  const exercises = React.useMemo(() => collectExercises(segments), [segments]);
  const [modState, setModState] = useState<Record<string, ModState>>(() =>
    buildInitialModState(exercises, initialMods),
  );

  function updateState(id: string, patch: Partial<ModState>) {
    setModState((prev) => ({ ...prev, [id]: { ...prev[id]!, ...patch } }));
  }

  function toggleActive(ex: ExerciseMeta) {
    const current = modState[ex.id];
    if (!current) return;
    if (current.active) {
      updateState(ex.id, { active: false, skipped: false });
    } else {
      updateState(ex.id, { active: true, skipped: false });
    }
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
        <div className="text-4xl">📝</div>
        <h2 className="text-xl font-bold text-center">{i18n("anyModifications97c3e24")}</h2>
        <p className="text-sm text-center max-w-xs" style={{ color: "var(--muted)" }}>
          {i18n("flagExercisesYouSkippedOrChangedPreFilledc1fea5a")}
        </p>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-4 space-y-2">
        {exercises.map((ex) => {
          const s = modState[ex.id];
          if (!s) return null;
          const hasPrescription = ex.prescription_value != null;
          const hasLoad = ex.load_value != null;
          const hasSets = (ex.sets ?? 0) > 1;

          return (
            <div
              key={ex.id}
              className="rounded-2xl p-4"
              style={{
                background: "var(--panel)",
                border: `1px solid ${s.active ? (s.skipped ? "color-mix(in srgb, var(--danger, var(--primary)) 40%, transparent)" : "var(--warning)") : "var(--border)"}`,
              }}
            >
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm font-semibold truncate" style={{ color: "var(--text)" }}>
                    {ex.name}
                  </p>
                  {(hasSets || hasPrescription || hasLoad) && (
                    <p className="text-xs mt-0.5" style={{ color: "var(--dim)" }}>
                      {[
                        hasSets ? (ex.sets) + " sets" : null,
                        hasPrescription ? (ex.prescription_value) + " " + (ex.prescription_unit ?? "").trim() : null,
                        hasLoad
                          ? ex.load_mode === "pct_1rm"
                            ? (ex.load_value) + i18n("percentOneRepMaxUnit")
                            : (ex.load_value) + " " + i18n("kilogramsUnit")
                          : null,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  )}
                </div>
                <button
                  type="button"
                  onClick={() => toggleActive(ex)}
                  className="shrink-0 rounded-xl px-3 py-1.5 text-xs font-semibold"
                  style={{
                    background: s.active
                      ? s.skipped
                        ? "color-mix(in srgb, var(--danger, var(--primary)) 18%, transparent)"
                        : "color-mix(in srgb, var(--warning) 18%, transparent)"
                      : "var(--panel-muted)",
                    color: s.active
                      ? s.skipped
                        ? "var(--danger, var(--primary))"
                        : "var(--warning)"
                      : "var(--dim)",
                    border: "1px solid var(--border)",
                  }}
                >
                  {s.active ? (s.skipped ? i18n("skipped5a000ad") : i18n("modifiede744110")) : i18n("mark31e9697")}
                </button>
              </div>

              {s.active && !s.skipped && (
                <div className="mt-3 space-y-2">
                  {hasSets && (
                    <div className="flex items-center gap-2">
                      <span className="text-xs w-20 shrink-0" style={{ color: "var(--dim)" }}>
                        {i18n("sets2ab262f")}
                      </span>
                      <input
                        type="number"
                        inputMode="numeric"
                        className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold outline-none"
                        style={{
                          background: "var(--panel-muted)",
                          border: "1px solid var(--border)",
                          color: "var(--text)",
                        }}
                        value={s.actualSets}
                        placeholder={String(ex.sets)}
                        onChange={(e) => updateState(ex.id, { actualSets: e.target.value })}
                      />
                    </div>
                  )}
                  {hasPrescription && (
                    <div className="flex items-center gap-2">
                      <span className="text-xs w-20 shrink-0" style={{ color: "var(--dim)" }}>
                        {ex.prescription_unit ?? i18n("reps702045f")}
                      </span>
                      <input
                        type="number"
                        inputMode="numeric"
                        className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold outline-none"
                        style={{
                          background: "var(--panel-muted)",
                          border: "1px solid var(--border)",
                          color: "var(--text)",
                        }}
                        value={s.actualValue}
                        placeholder={String(ex.prescription_value)}
                        onChange={(e) => updateState(ex.id, { actualValue: e.target.value })}
                      />
                    </div>
                  )}
                  {hasLoad && (
                    <div className="flex items-center gap-2">
                      <span className="text-xs w-20 shrink-0" style={{ color: "var(--dim)" }}>
                        {ex.load_mode === "pct_1rm" ? i18n("percentOneRepMaxUnit") : i18n("kilogramsUnit")}
                      </span>
                      <input
                        type="number"
                        inputMode="decimal"
                        className="flex-1 rounded-xl px-3 py-2 text-sm font-semibold outline-none"
                        style={{
                          background: "var(--panel-muted)",
                          border: "1px solid var(--border)",
                          color: "var(--text)",
                        }}
                        value={s.actualLoad}
                        placeholder={String(ex.load_value)}
                        onChange={(e) => updateState(ex.id, { actualLoad: e.target.value })}
                      />
                    </div>
                  )}
                </div>
              )}

              {s.active && (
                <div className="mt-3 flex gap-2">
                  {!s.skipped && (
                    <button
                      type="button"
                      onClick={() => updateState(ex.id, { skipped: true })}
                      className="rounded-xl px-3 py-1.5 text-xs font-semibold"
                      style={{
                        background: "color-mix(in srgb, var(--danger, var(--primary)) 10%, transparent)",
                        color: "var(--danger, var(--primary))",
                        border: "1px solid color-mix(in srgb, var(--danger, var(--primary)) 22%, transparent)",
                      }}
                    >
                      {i18n("iSkippedThisCompletely17f47b6")}
                    </button>
                  )}
                  {s.skipped && (
                    <button
                      type="button"
                      onClick={() => updateState(ex.id, { skipped: false })}
                      className="rounded-xl px-3 py-1.5 text-xs font-semibold"
                      style={{
                        background: "var(--panel-muted)",
                        color: "var(--dim)",
                        border: "1px solid var(--border)",
                      }}
                    >
                      {i18n("undoSkip7bc61ef")}
                    </button>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div className="p-4 pt-0">
        <button
          type="button"
          onClick={() => onNext(buildModifications(exercises, modState))}
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
                    {score.value} {score.unit ?? ""}
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
                  key={(mod.exercise_id) + "-" + (i)}
                  className="flex justify-between items-center rounded-xl px-4 py-2.5"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                >
                  <span className="text-sm truncate" style={{ color: "var(--muted)" }}>
                    {exerciseMap[mod.exercise_id] ?? mod.exercise_id}
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
                    {mod.type === "skipped" ? i18n("skipped5a000ad") : i18n("modified19a532c")}
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
