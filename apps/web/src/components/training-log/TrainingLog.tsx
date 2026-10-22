"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchTrainingLogSources,
  updateTrainingLogEntry,
  voidTrainingLogEntry,
  type TrainingLogEntry,
  type TrainingLogSourceType,
} from "@/api/training-log";
import { localizeError } from "@/i18n/presentation";
import { CommentList } from "@/components/journal/CommentList";
import { useJournalCommentWriter } from "@/hooks/useJournalCommentWriter";
import { useOutboxCommand } from "@/hooks/useOutboxCommand";
import { FeltStep } from "@/components/wod-goals/FeltStep";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  buildCreatePayload,
  buildUpdatePayload,
  commentDraftFromForm,
  emptyExerciseRow,
  emptyTrainingLogForm,
  formFromEntry,
  newIdempotencyKey,
  sectionsFromEntryScores,
  validateTrainingLogForm,
  type SelectedTrainingSource,
  type TrainingLogForm,
  type TrainingLogFormError,
} from "@/lib/training-log";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { DateTimeInput } from "@/components/ui/DateInput";

export const TRAINING_LOG_ENTRIES_KEY = ["training-log", "entries"] as const;
export const TRAINING_LOG_SOURCES_KEY = ["training-log", "sources"] as const;
const SOURCES_KEY = TRAINING_LOG_SOURCES_KEY;

const SOURCE_LABEL_KEYS: Record<TrainingLogSourceType, string> = {
  class: "trainingLogSourceClass",
  assigned_workout: "trainingLogSourceAssigned",
  library_workout: "trainingLogSourceLibrary",
  freeform: "trainingLogSourceFreeform",
};

const FORM_ERROR_KEYS: Record<TrainingLogFormError, string> = {
  titleRequired: "trainingLogErrorTitleRequired",
  performedAtRequired: "trainingLogErrorPerformedAtRequired",
  performedAtFuture: "trainingLogErrorPerformedAtFuture",
  durationInvalid: "trainingLogErrorDurationInvalid",
  exerciseNameRequired: "trainingLogErrorExerciseNameRequired",
  exerciseNumberInvalid: "trainingLogErrorExerciseNumberInvalid",
};

const LOAD_UNITS = ["kg", "lb"] as const;

const inputClass = "mt-1 w-full rounded-xl px-3 py-2 text-sm";
const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
const labelClass = "block text-xs font-semibold tracking-[0.16em]";

export type TrainingLogDialogState =
  | { mode: "closed" }
  | { mode: "pick" }
  | {
      mode: "create";
      source: SelectedTrainingSource;
      /** A prefilled form to review (voice logging, ADR-175); nothing is saved until the member confirms. */
      draft?: TrainingLogForm;
      /** What was heard, shown with the draft. */
      transcript?: string;
    }
  | { mode: "edit"; entry: TrainingLogEntry }
  | { mode: "void"; entry: TrainingLogEntry };

function browserTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

/** A comment on a performed row (`row:<n>`) names the row's exercise. */
function rowLabel(entry: TrainingLogEntry, exerciseId: string | null | undefined): string | null {
  const match = exerciseId?.match(/^row:(\d+)$/);
  if (!match) return null;
  return entry.performed_exercises[Number(match[1]) - 1]?.name ?? null;
}

/** One logged workout in Ημερολόγιο › Ροή, with edit and void (ADR-118). */
export function TrainingLogEntryCard({
  entry,
  locale,
  onEdit,
  onVoid,
  badge,
  device,
}: {
  entry: TrainingLogEntry;
  locale: string;
  onEdit: () => void;
  onVoid: () => void;
  /** The entry's visibility badge, where the journal shows one. */
  badge?: ReactNode;
  /** The watch's numbers once a device matched this workout (ADR-161). */
  device?: ReactNode;
}) {
  const i18n = useUiTranslations();
  const voided = entry.status === "voided";
  const performedAt = new Date(entry.performed_at_utc).toLocaleString(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  });

  return (
    <li
      className="rounded-2xl p-4"
      style={{
        background: "var(--panel-muted)",
        border: "1px solid var(--border)",
        opacity: voided ? 0.6 : 1,
      }}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n(SOURCE_LABEL_KEYS[entry.source_type])}
            {voided ? ` · ${i18n("trainingLogVoided")}` : ""}
          </p>
          <p
            className="mt-1 break-words text-base font-semibold"
            style={{ color: "var(--text)", textDecoration: voided ? "line-through" : undefined }}
          >
            {entry.title}
          </p>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
            {performedAt}
            {typeof entry.duration_seconds === "number"
              ? ` · ${i18n("trainingLogDurationMinutes", { minutes: Math.round(entry.duration_seconds / 60) })}`
              : ""}
            {typeof entry.perceived_effort === "number"
              ? ` · ${i18n("trainingLogEffortValue", { effort: entry.perceived_effort })}`
              : ""}
          </p>
          {device}
          {badge ? <div className="mt-1">{badge}</div> : null}
          {entry.comments.length > 0 ? (
            <div className="mt-2">
              <CommentList
                comments={entry.comments}
                anchorLabel={(comment) => rowLabel(entry, comment.exercise_id)}
              />
            </div>
          ) : null}
          {entry.performed_exercises.length > 0 ? (
            <ul className="mt-2 grid gap-1 text-sm" style={{ color: "var(--muted)" }}>
              {entry.performed_exercises.map((exercise, index) => (
                <li key={`${entry.id}-${index}`} className="break-words">
                  {[
                    exercise.name,
                    exercise.sets && exercise.reps != null ? `${exercise.sets}×${exercise.reps}` : null,
                    exercise.load != null ? `${exercise.load} ${exercise.load_unit ?? ""}`.trim() : null,
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
        {!voided ? (
          <div className="flex shrink-0 gap-2">
            <button
              type="button"
              className="rounded-full px-3 py-1.5 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
              onClick={onEdit}
            >
              {i18n("trainingLogEdit")}
            </button>
            <button
              type="button"
              className="rounded-full px-3 py-1.5 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--muted)" }}
              onClick={onVoid}
            >
              {i18n("trainingLogVoid")}
            </button>
          </div>
        ) : null}
      </div>
    </li>
  );
}

/** The log/edit/void dialog; Box › Καταγραφή opens it on a chosen source (ADR-137). */
export function TrainingLogDialog({
  state,
  token,
  onNavigate,
  onClose,
}: {
  state: Exclude<TrainingLogDialogState, { mode: "closed" }>;
  token: string;
  onNavigate: (state: TrainingLogDialogState) => void;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const heading =
    state.mode === "edit"
      ? i18n("trainingLogEditTitle")
      : state.mode === "void"
        ? i18n("trainingLogVoid")
        : i18n("trainingLogLogWorkout");

  return (
    <Dialog onClose={onClose} title={heading} size="lg">
          {state.mode === "pick" ? (
            <SourcePicker token={token} onSelect={(source) => onNavigate({ mode: "create", source })} />
          ) : state.mode === "void" ? (
            <VoidForm token={token} entry={state.entry} onDone={onClose} />
          ) : (
            <EntryForm
              token={token}
              state={state}
              onBack={state.mode === "create" && !state.draft ? () => onNavigate({ mode: "pick" }) : undefined}
              onDone={onClose}
            />
          )}
    </Dialog>
  );
}

/** Above a voice draft (ADR-175): review before saving, and what was heard. */
function VoiceDraftNotice({ transcript }: { transcript?: string }) {
  const t = useTranslations("VoiceLog");
  return (
    <div
      className="rounded-2xl px-4 py-3 text-sm"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
      data-testid="voice-draft-notice"
    >
      <p className="font-semibold">{t("draftNotice")}</p>
      {transcript ? (
        <details className="mt-1">
          <summary className="cursor-pointer text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("heard")}</summary>
          <p className="mt-1 break-words text-xs" style={{ color: "var(--muted)" }}>«{transcript}»</p>
        </details>
      ) : null}
    </div>
  );
}

function SourcePicker({ token, onSelect }: { token: string; onSelect: (source: SelectedTrainingSource) => void }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const [tab, setTab] = useState<TrainingLogSourceType>("class");
  const sourcesQuery = useQuery({ queryKey: SOURCES_KEY, queryFn: () => fetchTrainingLogSources(token) });
  const tabs: TrainingLogSourceType[] = ["class", "assigned_workout", "library_workout", "freeform"];

  const optionButton = (key: string, title: string, subtitle: string | null, source: SelectedTrainingSource) => (
    <li key={key}>
      <button
        type="button"
        className="w-full rounded-2xl px-4 py-3 text-start"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        onClick={() => onSelect(source)}
      >
        <span className="block break-words text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</span>
        {subtitle ? <span className="mt-0.5 block text-xs" style={{ color: "var(--muted)" }}>{subtitle}</span> : null}
      </button>
    </li>
  );

  const renderList = () => {
    if (tab === "freeform") {
      return (
        <div className="grid gap-3">
          <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("trainingLogFreeformHint")}</p>
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            onClick={() => onSelect({ sourceType: "freeform", referenceId: null, title: "", scoreableSections: [] })}
          >
            {i18n("trainingLogStartFreeform")}
          </button>
        </div>
      );
    }

    if (sourcesQuery.isPending) return <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("trainingLogLoading")}</p>;
    if (sourcesQuery.isError) {
      return <p className="text-sm" role="alert" style={{ color: "var(--danger)" }}>{localizeError(sourcesQuery.error, i18n)}</p>;
    }

    const sources = sourcesQuery.data;

    if (tab === "class") {
      if (sources.classes.length === 0) return <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("trainingLogNoClasses")}</p>;
      return (
        <ul className="grid gap-2">
          {sources.classes.map((item) =>
            optionButton(
              item.id,
              item.title,
              new Date(item.scheduled_at).toLocaleString(uiLocale, { dateStyle: "medium", timeStyle: "short" }),
              { sourceType: "class", referenceId: item.id, title: item.title, scoreableSections: item.scoreable_sections },
            ),
          )}
        </ul>
      );
    }

    if (tab === "assigned_workout") {
      if (sources.assignments.length === 0) return <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("trainingLogNoAssignments")}</p>;
      return (
        <ul className="grid gap-2">
          {sources.assignments.map((item) =>
            optionButton(
              item.id,
              item.title,
              new Date(`${item.scheduled_for}T00:00:00`).toLocaleDateString(uiLocale, { dateStyle: "medium" }),
              { sourceType: "assigned_workout", referenceId: item.id, title: item.title, scoreableSections: item.scoreable_sections },
            ),
          )}
        </ul>
      );
    }

    if (sources.library_workouts.length === 0) return <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("trainingLogNoLibrary")}</p>;
    return (
      <ul className="grid gap-2">
        {sources.library_workouts.map((item) =>
          optionButton(item.id, item.title, null, {
            sourceType: "library_workout",
            referenceId: item.id,
            title: item.title,
            scoreableSections: [],
          }),
        )}
      </ul>
    );
  };

  return (
    <div className="grid gap-4">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("trainingLogChooseSource")}</p>
      <div className="flex flex-wrap gap-2" role="tablist">
        {tabs.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            className="rounded-full px-3 py-1.5 text-sm font-semibold"
            style={{
              background: tab === value ? "var(--primary)" : "var(--panel-muted)",
              color: tab === value ? "var(--primary-contrast)" : "var(--muted)",
            }}
            onClick={() => setTab(value)}
          >
            {i18n(SOURCE_LABEL_KEYS[value])}
          </button>
        ))}
      </div>
      {renderList()}
    </div>
  );
}

function EntryForm({
  token,
  state,
  onBack,
  onDone,
}: {
  token: string;
  state: Extract<TrainingLogDialogState, { mode: "create" }> | { mode: "edit"; entry: TrainingLogEntry };
  onBack?: () => void;
  onDone: () => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("MemberApp.comments");
  const queryClient = useQueryClient();
  const sourceType = state.mode === "create" ? state.source.sourceType : state.entry.source_type;
  const sections =
    state.mode === "create" ? state.source.scoreableSections : sectionsFromEntryScores(state.entry);
  const [form, setForm] = useState<TrainingLogForm>(() =>
    state.mode === "create"
      ? (state.draft ?? emptyTrainingLogForm(new Date(), state.source.title))
      : formFromEntry(state.entry),
  );
  const [idempotencyKey] = useState(newIdempotencyKey);
  const [errors, setErrors] = useState<TrainingLogFormError[]>([]);
  const [queued, setQueued] = useState(false);
  const [feltEntryId, setFeltEntryId] = useState<string | null>(null);
  const submitCommand = useOutboxCommand();
  const commentWriter = useJournalCommentWriter();

  const mutation = useMutation({
    // ADR-120: new entries go through the durable outbox (the form's
    // idempotency key is the operation id); edits stay online-only because
    // they carry an optimistic-lock version.
    mutationFn: async (): Promise<{ queued: boolean; createdId?: string }> => {
      if (state.mode === "create") {
        const outcome = await submitCommand<TrainingLogEntry, unknown>(
          "training_log.create",
          buildCreatePayload(form, state.source, { idempotencyKey, timezone: browserTimezone() }),
        );
        return outcome.status === "queued" ? { queued: true } : { queued: false, createdId: outcome.result?.id };
      }

      await updateTrainingLogEntry(token, state.entry.id, buildUpdatePayload(form, state.entry, sections, browserTimezone()));
      const draft = commentDraftFromForm(form, state.entry.id);
      if (draft) await commentWriter.save(draft);
      return { queued: false };
    },
    onSuccess: async (result) => {
      if (result.queued) {
        setQueued(true);
        return;
      }
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["training-log"] }),
        queryClient.invalidateQueries({ queryKey: ["landing"] }),
      ]);
      // «Τι ένιωσες;» needs the entry on the server; a queued entry skips it.
      if (result.createdId) setFeltEntryId(result.createdId);
      else onDone();
    },
  });

  const update = (patch: Partial<TrainingLogForm>) => setForm((current) => ({ ...current, ...patch }));
  const updateRow = (index: number, patch: Partial<TrainingLogForm["exercises"][number]>) =>
    setForm((current) => ({
      ...current,
      exercises: current.exercises.map((row, rowIndex) => (rowIndex === index ? { ...row, ...patch } : row)),
    }));

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const nextErrors = validateTrainingLogForm(form, sourceType, new Date());
    setErrors(nextErrors);
    if (nextErrors.length === 0) mutation.mutate();
  };

  if (feltEntryId) {
    return <FeltStep entryKind="training_log" entryId={feltEntryId} layout="inline" onDone={() => onDone()} />;
  }

  return (
    <form className="grid gap-4" onSubmit={submit} noValidate>
      {state.mode === "create" && state.draft ? <VoiceDraftNotice transcript={state.transcript} /> : null}
      {sourceType === "freeform" ? (
        <label className={labelClass} style={{ color: "var(--dim)" }}>
          {i18n("trainingLogFormTitle")}
          <input
            className={inputClass}
            style={inputStyle}
            value={form.title}
            maxLength={160}
            onChange={(event) => update({ title: event.target.value })}
          />
        </label>
      ) : (
        <div>
          <p className={labelClass} style={{ color: "var(--dim)" }}>{i18n(SOURCE_LABEL_KEYS[sourceType])}</p>
          <p className="mt-1 break-words text-base font-semibold" style={{ color: "var(--text)" }}>{form.title}</p>
        </div>
      )}

      <label className={labelClass} style={{ color: "var(--dim)" }}>
        {i18n("trainingLogFormPerformedAt")}
        <DateTimeInput
          className={inputClass}
          style={inputStyle}
          value={form.performedAt}
          onValueChange={(value) => update({ performedAt: value })}
        />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className={labelClass} style={{ color: "var(--dim)" }}>
          {i18n("trainingLogFormDuration")}
          <input
            inputMode="numeric"
            className={inputClass}
            style={inputStyle}
            value={form.durationMinutes}
            onChange={(event) => update({ durationMinutes: event.target.value })}
          />
        </label>
        <label className={labelClass} style={{ color: "var(--dim)" }}>
          {i18n("trainingLogFormEffort")}
          <Select
            className={inputClass}
            style={inputStyle}
            value={form.perceivedEffort}
            onValueChange={(value) => update({ perceivedEffort: value })}
          >
            <option value="">{i18n("trainingLogFormEffortNone")}</option>
            {Array.from({ length: 10 }, (_, index) => String(index + 1)).map((value) => (
              <option key={value} value={value}>{value}</option>
            ))}
          </Select>
        </label>
      </div>

      {sections.length > 0 ? (
        <fieldset className="grid gap-2">
          <legend className={labelClass} style={{ color: "var(--dim)" }}>{i18n("trainingLogFormScores")}</legend>
          {sections.map((section) => (
            <label key={section.id} className="text-sm" style={{ color: "var(--text)" }}>
              {section.name ?? i18n("trainingLogFormScores")}
              {section.unit ? ` (${section.unit})` : ""}
              <input
                className={inputClass}
                style={inputStyle}
                value={form.sectionScores[section.id] ?? ""}
                onChange={(event) =>
                  update({ sectionScores: { ...form.sectionScores, [section.id]: event.target.value } })
                }
              />
            </label>
          ))}
        </fieldset>
      ) : null}

      <fieldset className="grid gap-2">
        <legend className={labelClass} style={{ color: "var(--dim)" }}>{i18n("trainingLogFormExercises")}</legend>
        {form.exercises.map((row, index) => (
          <div key={index} className="grid grid-cols-6 gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
            <input
              aria-label={i18n("trainingLogFormExerciseName")}
              placeholder={i18n("trainingLogFormExerciseName")}
              className={`${inputClass} col-span-6`}
              style={inputStyle}
              value={row.name}
              maxLength={120}
              onChange={(event) => updateRow(index, { name: event.target.value })}
            />
            <input
              aria-label={i18n("trainingLogFormSets")}
              placeholder={i18n("trainingLogFormSets")}
              inputMode="numeric"
              className={`${inputClass} col-span-2`}
              style={inputStyle}
              value={row.sets}
              onChange={(event) => updateRow(index, { sets: event.target.value })}
            />
            <input
              aria-label={i18n("trainingLogFormReps")}
              placeholder={i18n("trainingLogFormReps")}
              inputMode="numeric"
              className={`${inputClass} col-span-2`}
              style={inputStyle}
              value={row.reps}
              onChange={(event) => updateRow(index, { reps: event.target.value })}
            />
            <input
              aria-label={i18n("trainingLogFormLoad")}
              placeholder={i18n("trainingLogFormLoad")}
              inputMode="decimal"
              className={`${inputClass} col-span-1`}
              style={inputStyle}
              value={row.load}
              onChange={(event) => updateRow(index, { load: event.target.value })}
            />
            <Select
              aria-label={i18n("trainingLogFormLoad")}
              className={`${inputClass} col-span-1`}
              style={inputStyle}
              value={row.loadUnit}
              onValueChange={(value) => updateRow(index, { loadUnit: value === "lb" ? "lb" : "kg" })}
            >
              {LOAD_UNITS.map((unit) => (
                <option key={unit} value={unit}>{unit}</option>
              ))}
            </Select>
            <button
              type="button"
              className="col-span-6 text-start text-xs font-semibold"
              style={{ color: "var(--muted)" }}
              onClick={() => update({ exercises: form.exercises.filter((_, rowIndex) => rowIndex !== index) })}
            >
              {i18n("trainingLogFormRemoveExercise")}
            </button>
          </div>
        ))}
        <button
          type="button"
          className="justify-self-start rounded-full px-3 py-1.5 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          onClick={() => update({ exercises: [...form.exercises, emptyExerciseRow()] })}
        >
          {i18n("trainingLogFormAddExercise")}
        </button>
      </fieldset>

      {state.mode === "edit" && state.entry.comments.length > 0 ? (
        <CommentList
          comments={state.entry.comments}
          anchorLabel={(comment) => rowLabel(state.entry, comment.exercise_id)}
          onDelete={async (comment) => {
            await commentWriter.remove(comment.id);
            await queryClient.invalidateQueries({ queryKey: ["training-log"] });
          }}
        />
      ) : null}

      <label className={labelClass} style={{ color: "var(--dim)" }}>
        {t("logComment")}
        <textarea
          className={`${inputClass} min-h-[96px]`}
          style={inputStyle}
          value={form.comment}
          maxLength={4000}
          placeholder={t("bodyPlaceholder")}
          onChange={(event) => update({ comment: event.target.value })}
        />
      </label>

      {errors.length > 0 ? (
        <ul className="grid gap-1 text-sm" role="alert" style={{ color: "var(--danger)" }}>
          {errors.map((error) => <li key={error}>{i18n(FORM_ERROR_KEYS[error])}</li>)}
        </ul>
      ) : null}
      {queued && !mutation.isError ? (
        <p className="text-sm" role="status" style={{ color: "var(--text-soft)" }}>{i18n("outboxQueuedNotice")}</p>
      ) : null}
      {mutation.isError ? (
        <p className="text-sm" role="alert" style={{ color: "var(--danger)" }}>{localizeError(mutation.error, i18n)}</p>
      ) : null}

      <div className="flex flex-wrap justify-end gap-2">
        {onBack ? (
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            onClick={onBack}
          >
            {i18n("trainingLogBack")}
          </button>
        ) : null}
        <button
          type="submit"
          disabled={mutation.isPending}
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)", opacity: mutation.isPending ? 0.7 : 1 }}
        >
          {mutation.isPending ? i18n("trainingLogSaving") : i18n("trainingLogSave")}
        </button>
      </div>
    </form>
  );
}

function VoidForm({ token, entry, onDone }: { token: string; entry: TrainingLogEntry; onDone: () => void }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [reason, setReason] = useState("");

  const mutation = useMutation({
    mutationFn: () =>
      voidTrainingLogEntry(token, entry.id, {
        reason: reason.trim() === "" ? null : reason.trim(),
        expected_version: entry.lock_version,
      }),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["training-log"] }),
        queryClient.invalidateQueries({ queryKey: ["landing"] }),
      ]);
      onDone();
    },
  });

  return (
    <div className="grid gap-4">
      <p className="text-sm" style={{ color: "var(--text)" }}>{i18n("trainingLogVoidConfirm")}</p>
      <p className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>{entry.title}</p>
      <label className={labelClass} style={{ color: "var(--dim)" }}>
        {i18n("trainingLogVoidReason")}
        <input
          className={inputClass}
          style={inputStyle}
          value={reason}
          maxLength={500}
          onChange={(event) => setReason(event.target.value)}
        />
      </label>
      {mutation.isError ? (
        <p className="text-sm" role="alert" style={{ color: "var(--danger)" }}>{localizeError(mutation.error, i18n)}</p>
      ) : null}
      <div className="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          onClick={onDone}
        >
          {i18n("trainingLogCancel")}
        </button>
        <button
          type="button"
          disabled={mutation.isPending}
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)", opacity: mutation.isPending ? 0.7 : 1 }}
          onClick={() => mutation.mutate()}
        >
          {mutation.isPending ? i18n("trainingLogSaving") : i18n("trainingLogVoidAction")}
        </button>
      </div>
    </div>
  );
}
