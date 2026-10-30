"use client";





import { useTranslations } from "next-intl";
import {useUiTranslations} from "@/i18n/ui";
import { semanticLabel } from "@/i18n/presentation";
import { useId, useState } from "react";
import type { ExerciseModification, TimerSegment } from "@/api/executions";
import type { JournalComment } from "@/api/journal-comments";
import { CommentList } from "@/components/journal/CommentList";
import type { ChecklistStep } from "./WorkoutChecklist";
import { Dialog } from "@/components/ui/Dialog";

/** What the athlete recorded on a step: a change, text and tags, or both (ADR-140 §1). */
export type StepComment = { change: ExerciseModification | null; body: string | null; tags: string[] };

type Props = {
  segment: TimerSegment;
  step: ChecklistStep;
  /** Comments already on this exercise, listed under the form. */
  comments?: JournalComment[];
  pendingCommentIds?: string[];
  onSave: (comment: StepComment) => void;
  onDeleteComment?: (comment: JournalComment) => void;
  onClose: () => void;
};

function setIndexFromLabel(label: string | null) {
  if (!label) return 1;
  const parsed = Number(label.split("/")[0]);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

function patchId(segment: TimerSegment, step: ChecklistStep, field: string) {
  return [segment.segment_key, step.exerciseId, setIndexFromLabel(step.stepLabel), segment.round ?? 0, field].join(":");
}

export function ModificationModal({
  segment,
  step,
  comments = [],
  pendingCommentIds = [],
  onSave,
  onDeleteComment,
  onClose,
}: Props) {
  const i18n = useUiTranslations();
  const t = useTranslations("MemberApp.comments");
  const [body, setBody] = useState("");
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
  const titleId = useId();

  function handleSkip() {
    save({
      patch_id: patchId(segment, step, "skipped"),
      field: "skipped",
      section_id: segment.section_id,
      section_name: segment.section_name,
      segment_key: segment.segment_key,
      exercise_id: exercise.id,
      exercise_name: exercise.name,
      set_index: setIndexFromLabel(step.stepLabel),
      round_index: segment.round,
      canonical_value: false,
      actual_value: true,
      type: "skipped",
    });
  }

  function save(change: ExerciseModification | null) {
    onSave({ change, body: body.trim() || null, tags: [] });
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
    const field = loadChanged ? "load" : repsChanged ? "reps" : parsedActualSets !== exercise.sets ? "sets" : "prescription_value";
    const canonicalValue =
      field === "load"
        ? exercise.load_value
        : field === "sets"
          ? exercise.sets
          : exercise.prescription_value;
    const actual =
      field === "load"
        ? parsedActualLoad
        : field === "sets"
          ? parsedActualSets
          : parsedActualValue;

    const unchanged = actual === null || actual === canonicalValue;
    if (unchanged) {
      if (body.trim()) save(null);
      else onClose();
      return;
    }

    save({
      patch_id: patchId(segment, step, field),
      field,
      section_id: segment.section_id,
      section_name: segment.section_name,
      segment_key: segment.segment_key,
      exercise_id: exercise.id,
      exercise_name: exercise.name,
      set_index: setIndexFromLabel(step.stepLabel),
      round_index: segment.round,
      type,
      canonical_value: canonicalValue ?? "",
      actual_value: actual ?? "",
      unit: field === "load" ? (exercise.load_mode === "pct_1rm" ? "%" : "kg") : exercise.prescription_unit ?? null,
    });
  }

  return (
    <Dialog
      onClose={onClose}
      eyebrow={<span style={{ color: "var(--dim)" }}>{i18n("modifyStepbc84bb7")}</span>}
      title={exercise.name}
      titleId={titleId}
      description={step.stepLabel ? <span style={{ color: "var(--primary)" }}>{i18n("setLabel")} {step.stepLabel}</span> : undefined}
      size="lg"
      footer={
        <div className="w-full flex flex-col gap-2">
          <button
            type="button"
            onClick={handleSave}
            className="w-full rounded-2xl py-3.5 text-base font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {i18n("saveChanges179359b")}
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
            {i18n("iSkippedThisStepCompletely6410954")}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-2xl py-3 text-sm font-semibold"
            style={{ color: "var(--dim)" }}
          >
            {i18n("cancel77dfd21")}
          </button>
        </div>
      }
    >
        

        <div className="space-y-3 mb-6">
          {hasSets && (
            <div>
              <label className="block text-xs font-semibold mb-1" style={{ color: "var(--muted)" }}>
                {i18n("setsPrescribed68f6881")} {exercise.sets})
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
                  ? i18n("prescribedValue", {unit: semanticLabel(exercise.prescription_unit, i18n), value: exercise.prescription_value ?? 0})
                  : i18n("repetitionsPrescribedValue", {value: exercise.prescription_value ?? 0})}
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
                  ? i18n("loadPercentRmPrescribed", { value: exercise.load_value ?? 0 })
                  : i18n("loadKgPrescribed", { value: exercise.load_value ?? 0, unit: semanticLabel("kg", i18n) })}
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
              {i18n("noPrescribedValuesForThisExerciseUseThe2d5dd0b")}
            </p>
          )}

          <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {t("bodyLabel")}
            <textarea
              rows={3}
              maxLength={4000}
              placeholder={t("bodyPlaceholder")}
              className="mt-1 w-full resize-none rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={body}
              onChange={(event) => setBody(event.target.value)}
            />
          </label>
        </div>

        {comments.length > 0 ? (
          <div className="mb-4 max-h-48 overflow-y-auto">
            <CommentList
              comments={comments}
              pendingIds={pendingCommentIds}
              anchorLabel={() => exercise.name}
              onDelete={onDeleteComment}
            />
          </div>
        ) : null}
    </Dialog>
  );
}
