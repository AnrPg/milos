"use client";

import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import {
  describePath,
  fieldOf,
  formatFieldValue,
  getAtPath,
  isAssumptionIssue,
  isTextCorrection,
  openIssues,
  openSuggestions,
  parseFieldInput,
  type AnalysisIssue,
  type AnalysisSuggestion,
  type BlockingProblem,
  type CanonicalWorkout,
  type ReviewState,
} from "@/lib/free-text-analysis";

export type AnalysisStatus = "idle" | "loading" | "ready" | "error";

type Props = {
  review: ReviewState | null;
  status: AnalysisStatus;
  errorCode: string | null;
  stale: boolean;
  hasText: boolean;
  blocking: BlockingProblem[];
  showBlocking: boolean;
  notice: string | null;
  onAnalyze: () => void;
  onAccept: (issue: AnalysisIssue, value?: unknown) => void;
  onReject: (issue: AnalysisIssue) => void;
  onUndo: (issue: AnalysisIssue) => void;
  onAddSuggestion: (suggestion: AnalysisSuggestion, value: unknown, alsoInText: boolean) => void;
  onDismissSuggestion: (suggestion: AnalysisSuggestion) => void;
  onInsertExample: () => void;
};

type Translate = ReturnType<typeof useTranslations>;

const KNOWN_FIELDS = new Set([
  "title", "type", "subtitle", "description", "difficulty", "estimated_duration_seconds", "equipment", "tags",
  "name", "note", "timer_config", "sets", "prescription_value", "prescription_unit", "load_value", "load_mode",
  "rest_seconds", "tempo", "text",
]);

export function FreeTextAnalysisPanel(props: Props) {
  const t = useTranslations("WorkoutAssistant");
  const { review, status, errorCode, stale, hasText, blocking, showBlocking, notice } = props;
  const issues = review ? openIssues(review) : [];
  const resolvedIssues = review ? review.analysis.issues.filter((issue) => review.issues[issue.id]) : [];
  const suggestions = review ? openSuggestions(review) : [];
  const busy = status === "loading";

  return (
    <div className="space-y-4" aria-busy={busy}>
      <div className="rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
        <h2 className="text-base font-black" style={{ color: "var(--text)" }}>{t("title")}</h2>
        <p className="mt-1 text-sm leading-6" style={{ color: "var(--muted)" }}>{t("intro")}</p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={props.onAnalyze}
            disabled={busy || !hasText}
            className="rounded-xl px-4 py-2 text-sm font-black disabled:opacity-40"
            style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
          >
            {busy ? t("analyzing") : review ? t("reanalyze") : t("analyze")}
          </button>
          {!hasText ? (
            <button
              type="button"
              onClick={props.onInsertExample}
              className="rounded-xl px-4 py-2 text-sm font-bold"
              style={{ border: "1px solid var(--dim)", color: "var(--text)" }}
            >
              {t("insertExample")}
            </button>
          ) : null}
        </div>
        <p role="status" aria-live="polite" className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          {busy ? t("analyzingHint") : stale && review ? t("stale") : ""}
        </p>
      </div>

      {status === "error" && errorCode ? (
        <Callout tone="warning">{errorMessage(t, errorCode)}</Callout>
      ) : null}

      {notice ? <Callout tone="info">{notice}</Callout> : null}

      {showBlocking && blocking.length > 0 ? (
        <Callout tone="error">
          <p className="font-bold">{t("blockingTitle")}</p>
          <ul className="mt-1 list-disc ps-5">
            {blocking.map((problem) => (
              <li key={problem.path}>
                {pathText(t, problem.path)}: {problem.reason === "too_short" ? t("blockingTooShort") : t("blockingRequired")}
              </li>
            ))}
          </ul>
        </Callout>
      ) : null}

      {!review && !busy ? <TipsCard t={t} /> : null}

      {review ? (
        <>
          <Summary t={t} review={review} openCount={issues.length} />

          {issues.length > 0 ? (
            <section aria-labelledby="assistant-issues-heading" className="space-y-3">
              <h3 id="assistant-issues-heading" className="text-xs font-black uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                {t("issuesHeading", { count: issues.length })}
              </h3>
              {issues.map((issue) => (
                <IssueCard key={issue.id} t={t} issue={issue} workout={review.workout} onAccept={props.onAccept} onReject={props.onReject} />
              ))}
            </section>
          ) : (
            <Callout tone="success">{t("allClear")}</Callout>
          )}

          {suggestions.length > 0 ? (
            <section aria-labelledby="assistant-suggestions-heading" className="space-y-3">
              <h3 id="assistant-suggestions-heading" className="text-xs font-black uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                {t("suggestionsHeading", { count: suggestions.length })}
              </h3>
              {suggestions.map((suggestion) => (
                <SuggestionCard key={suggestion.id} t={t} suggestion={suggestion} onAdd={props.onAddSuggestion} onDismiss={props.onDismissSuggestion} />
              ))}
            </section>
          ) : null}

          {resolvedIssues.length > 0 ? (
            <details className="rounded-2xl border p-3" style={{ borderColor: "var(--dim)" }}>
              <summary className="cursor-pointer text-sm font-bold" style={{ color: "var(--muted)" }}>
                {t("resolvedHeading", { count: resolvedIssues.length })}
              </summary>
              <ul className="mt-2 space-y-2">
                {resolvedIssues.map((issue) => (
                  <li key={issue.id} className="flex flex-wrap items-center justify-between gap-2 text-sm" style={{ color: "var(--text)" }}>
                    <span>
                      {pathText(t, issue.path)} ·{" "}
                      {review.issues[issue.id] === "accepted"
                        ? t("accepted")
                        : isTextCorrection(issue)
                          ? t("rejectedText")
                          : issue.required
                          ? t("rejectedRequired")
                          : t("rejectedOptional")}
                    </span>
                    <button type="button" className="text-xs font-bold underline" style={{ color: "var(--primary)" }} onClick={() => props.onUndo(issue)}>
                      {t("undo")}
                    </button>
                  </li>
                ))}
              </ul>
            </details>
          ) : null}

          <StructurePreview t={t} workout={review.workout} />
        </>
      ) : null}
    </div>
  );
}

function IssueCard({
  t,
  issue,
  workout,
  onAccept,
  onReject,
}: {
  t: Translate;
  issue: AnalysisIssue;
  workout: CanonicalWorkout;
  onAccept: Props["onAccept"];
  onReject: Props["onReject"];
}) {
  const [draft, setDraft] = useState(() => formatFieldValue(issue.path, issue.suggestion?.value ?? getAtPath(workout, issue.path)));
  const [invalid, setInvalid] = useState(false);
  const suggestion = issue.suggestion;
  const hasSuggestedValue = suggestion?.value !== null && suggestion?.value !== undefined;
  const isError = issue.severity === "error";
  // A value the assistant inferred rather than read: Keep or Reject (clear).
  const isAssumption = isAssumptionIssue(issue);

  function applyTyped() {
    const value = parseFieldInput(issue.path, draft);
    if (value === undefined) {
      setInvalid(true);
      return;
    }
    setInvalid(false);
    onAccept(issue, value);
  }

  return (
    <article
      className="rounded-2xl border p-4"
      style={{
        borderColor: isError
          ? "var(--danger)"
          : isAssumption
            ? "var(--dim)"
            : "color-mix(in srgb, var(--warning) 55%, var(--dim))",
        background: "var(--card)",
      }}
    >
      <div className="flex flex-wrap items-center gap-2">
        <span
          className="rounded-full px-2 py-0.5 text-[11px] font-black uppercase tracking-wide"
          style={{
            background: isError
              ? "color-mix(in srgb, var(--danger) 16%, transparent)"
              : isAssumption
                ? "var(--bg)"
                : "color-mix(in srgb, var(--warning) 16%, transparent)",
            color: isError ? "var(--danger)" : isAssumption ? "var(--primary)" : "var(--warning)",
          }}
        >
          {isError ? t("severityError") : isAssumption ? t("severityAssumption") : t("severityWarning")}
        </span>
        {issue.required ? (
          <span className="text-[11px] font-bold uppercase" style={{ color: "var(--muted)" }}>{t("requiredBadge")}</span>
        ) : null}
        <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{pathText(t, issue.path)}</span>
      </div>

      <p className="mt-2 text-sm leading-6" style={{ color: "var(--text)" }}>{issueMessage(t, issue)}</p>

      {suggestion?.text_edit ? (
        <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          <del>{suggestion.text_edit.find}</del> → <ins className="font-bold no-underline" style={{ color: "var(--success, var(--primary))" }}>{suggestion.text_edit.replace}</ins>
        </p>
      ) : null}

      {!hasSuggestedValue && !suggestion?.text_edit && fieldOf(issue.path) !== "timer_config" ? (
        <div className="mt-3">
          <label className="block text-xs font-bold" style={{ color: "var(--muted)" }}>
            {t("typeValue")}
            <input
              value={draft}
              onChange={(event) => {
                setDraft(event.target.value);
                setInvalid(false);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter") applyTyped();
              }}
              aria-invalid={invalid}
              className="mt-1 w-full rounded-lg border px-3 py-2 text-sm outline-none"
              style={{ background: "var(--bg)", borderColor: invalid ? "var(--danger)" : "var(--dim)", color: "var(--text)" }}
            />
          </label>
          {invalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("invalidTyped")}</p> : null}
        </div>
      ) : null}

      <div className="mt-3 grid grid-cols-2 gap-2">
        <button
          type="button"
          onClick={() => (hasSuggestedValue || suggestion?.text_edit ? onAccept(issue) : applyTyped())}
          className="rounded-xl px-3 py-2 text-sm font-black"
          style={{ background: "var(--text)", color: "var(--bg)" }}
        >
          {isAssumption
            ? t("keepAssumption")
            : hasSuggestedValue || suggestion?.text_edit
              ? suggestion?.label || t("accept")
              : t("apply")}
        </button>
        <button
          type="button"
          onClick={() => onReject(issue)}
          className="rounded-xl px-3 py-2 text-sm font-black"
          style={{ border: "1px solid var(--text)", color: "var(--text)" }}
          title={rejectHint(t, issue)}
        >
          {t("reject")}
        </button>
      </div>
      <p className="mt-2 text-[11px]" style={{ color: "var(--muted)" }}>
        {rejectHint(t, issue)}
      </p>
    </article>
  );
}

function SuggestionCard({
  t,
  suggestion,
  onAdd,
  onDismiss,
}: {
  t: Translate;
  suggestion: AnalysisSuggestion;
  onAdd: Props["onAddSuggestion"];
  onDismiss: Props["onDismissSuggestion"];
}) {
  const [draft, setDraft] = useState(() => formatFieldValue(suggestion.path, suggestion.value));
  const [alsoInText, setAlsoInText] = useState(Boolean(suggestion.text_insert));
  const [invalid, setInvalid] = useState(false);
  const inputId = `suggestion-${suggestion.id}`;

  function add() {
    const value = parseFieldInput(suggestion.path, draft);
    if (value === undefined) {
      setInvalid(true);
      return;
    }
    onAdd(suggestion, value, alsoInText);
  }

  return (
    <article className="rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
      <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{pathText(t, suggestion.path)}</p>
      <p className="mt-1 text-sm leading-6" style={{ color: "var(--muted)" }}>
        {suggestion.reason || t(`why.${whyKey(suggestion.path)}`)}
      </p>
      <label htmlFor={inputId} className="mt-3 block text-xs font-bold" style={{ color: "var(--muted)" }}>
        {fieldUnitHint(t, suggestion.path)}
      </label>
      <input
        id={inputId}
        value={draft}
        placeholder={t("typeValuePlaceholder")}
        onChange={(event) => {
          setDraft(event.target.value);
          setInvalid(false);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") add();
        }}
        aria-invalid={invalid}
        className="mt-1 w-full rounded-lg border px-3 py-2 text-sm outline-none"
        style={{ background: "var(--bg)", borderColor: invalid ? "var(--danger)" : "var(--dim)", color: "var(--text)" }}
      />
      {invalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("invalidTyped")}</p> : null}
      {suggestion.text_insert ? (
        <label className="mt-2 flex items-start gap-2 text-xs" style={{ color: "var(--muted)" }}>
          <input type="checkbox" checked={alsoInText} onChange={(event) => setAlsoInText(event.target.checked)} />
          <span>
            {t("alsoInText")} <q>{suggestion.text_insert}</q>
          </span>
        </label>
      ) : null}
      <div className="mt-3 grid grid-cols-2 gap-2">
        <button type="button" onClick={add} className="rounded-xl px-3 py-2 text-sm font-black" style={{ background: "var(--text)", color: "var(--bg)" }}>
          {t("add")}
        </button>
        <button type="button" onClick={() => onDismiss(suggestion)} className="rounded-xl px-3 py-2 text-sm font-black" style={{ border: "1px solid var(--text)", color: "var(--text)" }}>
          {t("dismiss")}
        </button>
      </div>
    </article>
  );
}

function Summary({ t, review, openCount }: { t: Translate; review: ReviewState; openCount: number }) {
  const exercises = review.workout.sections.reduce((total, section) => total + section.exercises.length, 0);
  const items = [
    { label: t("summarySections"), value: review.workout.sections.length },
    { label: t("summaryExercises"), value: exercises },
    { label: t("summaryOpen"), value: openCount },
  ];

  return (
    <dl className="grid grid-cols-3 gap-2">
      {items.map((item) => (
        <div key={item.label} className="rounded-xl border px-3 py-2" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
          <dt className="text-[11px] font-bold uppercase tracking-wide" style={{ color: "var(--dim)" }}>{item.label}</dt>
          <dd className="text-lg font-black" style={{ color: "var(--text)" }}>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

function StructurePreview({ t, workout }: { t: Translate; workout: CanonicalWorkout }) {
  return (
    <details open className="rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
      <summary className="cursor-pointer text-sm font-black" style={{ color: "var(--text)" }}>{t("readAs")}</summary>
      <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
        {(["difficulty", "estimated_duration_seconds", "equipment", "tags"] as const).map((field) =>
          workout[field] && formatFieldValue(field, workout[field]) ? (
            <div key={field} className="contents">
              <dt style={{ color: "var(--muted)" }}>{fieldLabel(t, field)}</dt>
              <dd style={{ color: "var(--text)" }}>{formatFieldValue(field, workout[field])}</dd>
            </div>
          ) : null,
        )}
      </dl>
      {workout.sections.length === 0 ? (
        <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>{t("noBlocks")}</p>
      ) : (
        <ol className="mt-3 space-y-3">
          {workout.sections.map((section, sectionIndex) => (
            <li key={sectionIndex}>
              <p className="text-sm font-bold" style={{ color: "var(--text)" }}>
                {section.name || t("unnamed")}
                {section.timer_config?.type && section.timer_config.type !== "untimed" ? (
                  <span className="ms-2 rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "var(--bg)", color: "var(--primary)" }}>
                    {timerText(section.timer_config)}
                  </span>
                ) : null}
              </p>
              <ul className="mt-1 space-y-0.5 ps-4 text-sm" style={{ color: "var(--text)" }}>
                {section.exercises.map((exercise, exerciseIndex) => (
                  <li key={exerciseIndex} className="list-disc">
                    {exercise.interval_assignment ? (
                      <span className="me-1 font-bold" style={{ color: "var(--primary)" }}>
                        {slotText(t, section.timer_config?.type, exercise.interval_assignment)} ·
                      </span>
                    ) : null}
                    <span className={exercise.name ? "" : "italic"} style={exercise.name ? undefined : { color: "var(--danger)" }}>
                      {exercise.name || t("unnamed")}
                    </span>
                    <span style={{ color: "var(--muted)" }}>{prescriptionText(t, exercise)}</span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      )}
    </details>
  );
}

function TipsCard({ t }: { t: Translate }) {
  return (
    <div className="rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
      <p className="text-sm font-black" style={{ color: "var(--text)" }}>{t("tipsTitle")}</p>
      <ul className="mt-2 list-disc space-y-1 ps-5 text-sm" style={{ color: "var(--muted)" }}>
        <li>{t("tipOneLine")}</li>
        <li>{t("tipSetsReps")}</li>
        <li>{t("tipBlocks")}</li>
        <li>{t("tipTimers")}</li>
      </ul>
    </div>
  );
}

function Callout({ tone, children }: { tone: "info" | "warning" | "error" | "success"; children: ReactNode }) {
  const color = {
    info: "var(--primary)",
    warning: "var(--warning)",
    error: "var(--danger)",
    success: "var(--success)",
  }[tone];

  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      className="rounded-2xl border px-4 py-3 text-sm leading-6"
      style={{ borderColor: `color-mix(in srgb, ${color} 45%, transparent)`, background: `color-mix(in srgb, ${color} 10%, transparent)`, color: "var(--text)" }}
    >
      {children}
    </div>
  );
}

function issueMessage(t: Translate, issue: AnalysisIssue) {
  const params = (issue.params ?? {}) as Record<string, unknown>;

  switch (issue.code) {
    case "missing_title":
    case "missing_type":
    case "missing_section_name":
    case "missing_exercise_name":
      return t(`codes.${issue.code}`);
    case "too_short":
      return t("codes.too_short", { min: Number(params.min ?? 3) });
    case "invalid_value":
      return t("codes.invalid_value", { value: String(params.value ?? issue.current_value ?? "") });
    case "invalid_timer":
      return t("codes.invalid_timer", {
        format: String(params.format ?? "").replaceAll("_", " "),
        missing: Array.isArray(params.missing) ? params.missing.map((field) => fieldLabel(t, String(field))).join(", ") : "",
      });
    case "unknown_format":
      return t("codes.unknown_format", { value: String(params.value ?? "") });
    default:
      return issue.message || t("codes.generic");
  }
}

function rejectHint(t: Translate, issue: AnalysisIssue) {
  if (isTextCorrection(issue)) return t("rejectTextHint");
  if (isAssumptionIssue(issue) && !issue.required) return t("rejectAssumptionHint");
  return issue.required ? t("rejectRequiredHint") : t("rejectOptionalHint");
}

function errorMessage(t: Translate, code: string) {
  if (code === "analyzer_not_configured") return t("errors.notConfigured");
  if (code === "text_required") return t("errors.textRequired");
  if (code === "text_too_long") return t("errors.textTooLong");
  if (code === "analyzer_quota_exhausted") return t("errors.quotaExhausted");
  return t("errors.unavailable");
}

export function pathText(t: Translate, path: string) {
  const { section, exercise, field } = describePath(path);
  const parts = [];
  if (section) parts.push(t("pathSection", { number: section }));
  if (exercise) parts.push(t("pathExercise", { number: exercise }));
  parts.push(fieldLabel(t, field));
  return parts.join(" › ");
}

function fieldLabel(t: Translate, field: string) {
  return KNOWN_FIELDS.has(field) ? t(`fields.${field}`) : field;
}

function whyKey(path: string) {
  const field = fieldOf(path);
  return ["difficulty", "estimated_duration_seconds", "equipment", "description"].includes(field) ? field : "generic";
}

function fieldUnitHint(t: Translate, path: string) {
  const field = fieldOf(path);
  if (field === "estimated_duration_seconds") return t("hintMinutes");
  if (field === "equipment" || field === "tags") return t("hintList");
  if (field === "difficulty") return t("hintDifficulty");
  return t("hintValue");
}

function timerText(config: Record<string, unknown>) {
  const type = String(config.type ?? "").replaceAll("_", " ").toUpperCase();
  const details = Object.entries(config)
    .filter(([key]) => key !== "type")
    .map(([key, value]) => (key.endsWith("_seconds") && typeof value === "number" ? `${Math.round(value / 60)}′` : String(value)))
    .join(" · ");
  return details ? `${type} · ${details}` : type;
}

/** Which interval a complex_emom / even_odd exercise runs in. */
function slotText(t: Translate, format: unknown, slot: number) {
  if (format === "even_odd") return t(slot === 1 ? "oddIntervals" : "evenIntervals");
  return t("intervalSlot", { slot });
}

function prescriptionText(t: Translate, exercise: CanonicalWorkout["sections"][number]["exercises"][number]) {
  const parts: string[] = [];
  if (exercise.sets && exercise.prescription_value) parts.push(`${exercise.sets}×${exercise.prescription_value}`);
  else if (exercise.prescription_value) parts.push(String(exercise.prescription_value));
  else if (exercise.sets) parts.push(t("setsOnly", { count: exercise.sets }));
  if (exercise.prescription_unit && exercise.prescription_unit !== "reps") parts.push(t(`units.${exercise.prescription_unit}`));
  if (exercise.load_mode === "bw") parts.push(t("bodyweight"));
  else if (exercise.load_value != null) parts.push(exercise.load_mode === "pct_1rm" ? `${exercise.load_value}%` : `${exercise.load_value} kg`);
  if (exercise.rest_seconds) parts.push(t("restShort", { seconds: exercise.rest_seconds }));
  if (exercise.tempo) parts.push(exercise.tempo);
  return parts.length ? ` — ${parts.join(" · ")}` : "";
}
