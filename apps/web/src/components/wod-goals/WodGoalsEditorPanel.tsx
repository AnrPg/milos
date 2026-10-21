"use client";

import { useEffect, useReducer, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import type { GoalMuscle } from "@/api/wod-goals";
import { AnatomyThumb } from "@/components/anatomy/AnatomyThumb";
import { FITNESS_QUALITIES } from "@/lib/anatomy/qualities";
import {
  differsFromSuggestion,
  goalHighlights,
  goalPanelReducer,
  hasUnsavedChanges,
  initialGoalPanelState,
  musclesByRole,
  savePayload,
  timeDomainLabel,
} from "@/lib/wod-goals/goals";

import { FeltSummaryCard } from "./FeltSummaryCard";
import { MuscleChip, RoleLegend, ToggleChip } from "./GoalChips";
import { MusclePickerSheet, type PickerEntry } from "./MusclePickerSheet";
import { StimulusField } from "./StimulusField";
import { useAdminWorkoutGoals, useSaveAdminWorkoutGoals } from "./use-wod-goals";

type SaveStatus = "idle" | "saving" | "saved" | "error" | "invalid";

const AUTOSAVE_MS = 800;

/**
 * The coach's «Στόχοι» panel (Q1) for a workout or draft: the members toggle,
 * a small figure, muscles by role, qualities, stimulus and the suggestion
 * from the workout's exercises. Changes autosave; `refreshKey` changes after
 * each draft autosave so the suggestion follows the workout text.
 */
export function WodGoalsEditorPanel(props: { workoutId: string | null; refreshKey?: unknown; timeDomainSeconds?: number | null }) {
  const t = useTranslations("WodGoals");
  if (!props.workoutId) {
    return <p className="p-4 text-xs" style={{ color: "var(--muted)" }}>{t("needsDraft")}</p>;
  }
  return <GoalsPanel key={props.workoutId} {...props} workoutId={props.workoutId} />;
}

function GoalsPanel({ workoutId, refreshKey, timeDomainSeconds = null }: { workoutId: string; refreshKey?: unknown; timeDomainSeconds?: number | null }) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const query = useAdminWorkoutGoals(workoutId);
  const save = useSaveAdminWorkoutGoals(workoutId);
  const [state, dispatch] = useReducer(goalPanelReducer, initialGoalPanelState);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  const [retry, setRetry] = useState(0);
  const [pickerOpen, setPickerOpen] = useState(false);

  useEffect(() => {
    if (query.data) dispatch({ type: "loaded", response: query.data });
  }, [query.data]);

  // The draft was saved: read the suggestion again.
  const { refetch } = query;
  const lastRefresh = useRef(refreshKey);
  useEffect(() => {
    if (Object.is(lastRefresh.current, refreshKey)) return;
    lastRefresh.current = refreshKey;
    void refetch();
  }, [refreshKey, refetch]);

  const pending = state.loaded && hasUnsavedChanges(state);
  const latest = useRef({ draft: state.draft, revision: state.revision, mutate: save.mutateAsync, pending });
  useEffect(() => {
    latest.current = { draft: state.draft, revision: state.revision, mutate: save.mutateAsync, pending };
  });
  // Leaving (ribbon collapsed, editor closed) saves what the debounce still holds.
  useEffect(
    () => () => {
      const { draft, mutate, pending: unsaved } = latest.current;
      if (unsaved) void mutate(savePayload(draft)).catch(() => undefined);
    },
    [],
  );
  useEffect(() => {
    if (!pending) return;
    const timer = window.setTimeout(() => {
      const { draft, revision, mutate } = latest.current;
      setSaveStatus("saving");
      mutate(savePayload(draft))
        .then(() => {
          dispatch({ type: "savedRevision", revision });
          setSaveStatus("saved");
        })
        .catch((error: unknown) => {
          setSaveStatus(error instanceof ApiError && error.payload.code === "invalid_goals" ? "invalid" : "error");
        });
    }, AUTOSAVE_MS);
    return () => window.clearTimeout(timer);
  }, [pending, state.revision, retry]);

  if (query.isError && !state.loaded) {
    return (
      <div className="flex flex-wrap items-center gap-2 p-4 text-sm" role="alert" style={{ color: "var(--danger)" }}>
        {t("loadError")}
        <button type="button" className="font-semibold underline" onClick={() => void refetch()}>{t("retry")}</button>
      </div>
    );
  }
  if (!state.loaded) return <p className="p-4 text-xs" style={{ color: "var(--muted)" }}>…</p>;

  const { draft, suggestion } = state;
  const name = (id: string) => anatomy(`muscle.${id}`);

  return (
    <div className="flex flex-col gap-4 p-4" data-testid="wod-goals-panel">
      <div className="flex flex-col gap-1">
        <label className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
          <input type="checkbox" checked={draft.visible} onChange={(event) => dispatch({ type: "setVisible", visible: event.target.checked })} />
          {t("showToMembers")}
        </label>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("showToMembersHint")}</p>
        {state.inheritedFrom ? (
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft, var(--muted))" }}>{t("inherited")}</p>
        ) : null}
        <SaveLine
          status={saveStatus}
          saved={state.saved || Boolean(state.inheritedFrom)}
          onKeep={() => dispatch({ type: "setVisible", visible: draft.visible })}
          onRetry={() => setRetry((value) => value + 1)}
        />
      </div>

      <div className="flex items-start gap-3">
        <AnatomyThumb highlights={goalHighlights(draft.muscles)} view="both" height={140} className="shrink-0" />
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <RoleLegend />
          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            className="min-h-10 self-start rounded-xl px-3 text-xs font-bold"
            style={{ background: "var(--card, var(--panel-raised))", color: "var(--text)", border: "1px solid var(--dim, var(--border))" }}
          >
            {t("editOnBody")}
          </button>
        </div>
      </div>

      <section className="flex flex-col gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("muscles")}</h3>
        {draft.muscles.length === 0 ? (
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("noMuscles")}</p>
        ) : (
          musclesByRole(draft.muscles).map(([role, muscles]) => (
            <div key={role} className="flex flex-col gap-1">
              <p className="text-xs font-semibold" style={{ color: "var(--text-soft, var(--muted))" }}>{t(`legend.${role}`)}</p>
              <div className="flex flex-wrap gap-1.5">
                {muscles.map((muscle) => (
                  <MuscleChip
                    key={muscle.id}
                    label={name(muscle.id)}
                    role={muscle.role}
                    pressLabel={t("changeRole", { muscle: name(muscle.id), role: t(`role.${muscle.role}`) })}
                    onPress={() => dispatch({ type: "cycleRole", id: muscle.id })}
                    removeLabel={t("removeMuscle", { muscle: name(muscle.id) })}
                    onRemove={() => dispatch({ type: "setRole", id: muscle.id, role: null })}
                  />
                ))}
              </div>
            </div>
          ))
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("qualities")}</h3>
        <div className="flex flex-wrap gap-1.5">
          {FITNESS_QUALITIES.map((quality) => (
            <ToggleChip key={quality} pressed={draft.qualities.includes(quality)} onToggle={() => dispatch({ type: "toggleQuality", quality })}>
              {anatomy(`quality.${quality}`)}
            </ToggleChip>
          ))}
        </div>
      </section>

      <StimulusField
        value={draft.stimulus}
        timeDomain={timeDomainLabel(timeDomainSeconds)}
        onChange={(stimulus) => dispatch({ type: "setStimulus", stimulus })}
      />

      {suggestion ? (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl px-3 py-2 text-xs" style={{ background: "var(--bg)", color: "var(--muted)" }}>
          <span>
            {t("suggestionFrom", { count: suggestion.matched })}
            {suggestion.unmatched > 0 ? ` · ${t("unmatched", { count: suggestion.unmatched })}` : ""}
          </span>
          <button
            type="button"
            disabled={!differsFromSuggestion(state)}
            onClick={() => dispatch({ type: "resetToSuggestion" })}
            className="min-h-9 font-bold disabled:opacity-40"
            style={{ color: "var(--primary-strong, var(--primary))" }}
          >
            {t("resetSuggestion")}
          </button>
        </div>
      ) : null}

      <FeltSummaryCard source={{ kind: "workout", id: workoutId }} />

      {pickerOpen ? (
        <MusclePickerSheet
          title={t("picker.title")}
          hint={t("picker.hint")}
          entries={draft.muscles}
          roleOptions={["primary", "secondary", "stabilizer"]}
          onChange={(entries: PickerEntry[]) => dispatch({ type: "setMuscles", muscles: entries as GoalMuscle[] })}
          onClose={() => setPickerOpen(false)}
        />
      ) : null}
    </div>
  );
}

function SaveLine({ status, saved, onKeep, onRetry }: { status: SaveStatus; saved: boolean; onKeep: () => void; onRetry: () => void }) {
  const t = useTranslations("WodGoals");
  if (status === "error" || status === "invalid") {
    return (
      <p role="alert" className="flex flex-wrap items-center gap-2 text-xs font-semibold" style={{ color: "var(--danger)" }}>
        {status === "invalid" ? t("invalid") : t("status.error")}
        <button type="button" className="underline" onClick={onRetry}>{t("retry")}</button>
      </p>
    );
  }
  if (status === "saving") return <p role="status" className="text-xs" style={{ color: "var(--muted)" }}>{t("status.saving")}</p>;
  if (!saved) {
    return (
      <p className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--muted)" }}>
        {t("notSavedYet")}
        <button type="button" className="font-bold" style={{ color: "var(--primary-strong, var(--primary))" }} onClick={onKeep}>{t("keepSuggestion")}</button>
      </p>
    );
  }
  return status === "saved" ? <p role="status" className="text-xs" style={{ color: "var(--success, var(--muted))" }}>{t("status.saved")}</p> : null;
}
