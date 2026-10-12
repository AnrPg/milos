import type { FreeTextWorkoutAnalysis } from "@/api/workouts";

export type AnalysisIssue = FreeTextWorkoutAnalysis["issues"][number];
export type AnalysisSuggestion = FreeTextWorkoutAnalysis["suggestions"][number];

export type CanonicalExercise = {
  name: string | null;
  item_type: "exercise";
  sets?: number | null;
  prescription_value?: number | null;
  prescription_unit?: string | null;
  load_value?: number | null;
  load_mode?: string | null;
  rest_seconds?: number | null;
  tempo?: string | null;
  note?: string | null;
};

export type CanonicalSection = {
  name: string | null;
  note?: string | null;
  timer_config?: Record<string, unknown> | null;
  exercises: CanonicalExercise[];
};

export type CanonicalWorkout = {
  title: string | null;
  type: string | null;
  subtitle?: string | null;
  description?: string | null;
  difficulty?: string | null;
  estimated_duration_seconds?: number | null;
  equipment?: string[];
  tags?: string[];
  sections: CanonicalSection[];
};

export type IssueResolution = "accepted" | "rejected";
export type SuggestionResolution = "added" | "dismissed";

export type ReviewState = {
  analysis: FreeTextWorkoutAnalysis;
  workout: CanonicalWorkout;
  analyzedText: string;
  issues: Record<string, IssueResolution>;
  suggestions: Record<string, SuggestionResolution>;
};

export type BlockingProblem = { path: string; reason: "required" | "too_short" };

const LIST_FIELDS = new Set(["equipment", "tags"]);
const WORKOUT_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"];

export function createReviewState(analysis: FreeTextWorkoutAnalysis, analyzedText: string): ReviewState {
  return {
    analysis,
    workout: analysis.workout as unknown as CanonicalWorkout,
    analyzedText,
    issues: {},
    suggestions: {},
  };
}

export function isRequiredPath(path: string) {
  return (
    path === "title" ||
    path === "type" ||
    /^sections\.\d+\.name$/.test(path) ||
    /^sections\.\d+\.exercises\.\d+\.name$/.test(path)
  );
}

export function fieldOf(path: string) {
  return path.split(".").at(-1) ?? path;
}

export function getAtPath(source: unknown, path: string): unknown {
  return path.split(".").reduce<unknown>((value, segment) => {
    if (Array.isArray(value)) return value[Number(segment)];
    if (value && typeof value === "object") return (value as Record<string, unknown>)[segment];
    return undefined;
  }, source);
}

export function setAtPath<T>(source: T, path: string, nextValue: unknown): T {
  const [head, ...rest] = path.split(".");
  if (head === undefined) return source;

  if (Array.isArray(source)) {
    const index = Number(head);
    const copy = [...source];
    copy[index] = rest.length === 0 ? nextValue : setAtPath(copy[index], rest.join("."), nextValue);
    return copy as T;
  }

  const record = (source ?? {}) as Record<string, unknown>;
  return {
    ...record,
    [head]: rest.length === 0 ? nextValue : setAtPath(record[head], rest.join("."), nextValue),
  } as T;
}

export function emptyValueFor(path: string) {
  return LIST_FIELDS.has(fieldOf(path)) ? [] : null;
}

export function isEmptyValue(value: unknown) {
  return (
    value === null ||
    value === undefined ||
    (typeof value === "string" && value.trim() === "") ||
    (Array.isArray(value) && value.length === 0)
  );
}

/** Applies a value and keeps paired canonical fields consistent. */
export function writeField(workout: CanonicalWorkout, path: string, value: unknown): CanonicalWorkout {
  let next = setAtPath(workout, path, value);
  const parent = path.split(".").slice(0, -1).join(".");
  const field = fieldOf(path);

  if (field === "prescription_value") {
    const unitPath = `${parent}.prescription_unit`;
    if (isEmptyValue(value)) next = setAtPath(next, unitPath, null);
    else if (isEmptyValue(getAtPath(next, unitPath))) next = setAtPath(next, unitPath, "reps");
  }

  if (field === "load_value") {
    const modePath = `${parent}.load_mode`;
    if (isEmptyValue(value)) {
      if (getAtPath(next, modePath) !== "bw") next = setAtPath(next, modePath, null);
    } else if (isEmptyValue(getAtPath(next, modePath)) || getAtPath(next, modePath) === "bw") {
      next = setAtPath(next, modePath, "absolute");
    }
  }

  return next;
}

export function acceptIssue(state: ReviewState, issue: AnalysisIssue, value?: unknown): ReviewState {
  const nextValue = value !== undefined ? value : issue.suggestion?.value;
  const workout = nextValue === undefined || nextValue === null ? state.workout : writeField(state.workout, issue.path, nextValue);
  return { ...state, workout, issues: { ...state.issues, [issue.id]: "accepted" } };
}

export function rejectIssue(state: ReviewState, issue: AnalysisIssue): ReviewState {
  // Rejecting nullifies the field: optional fields are simply left out, while a
  // rejected required field blocks creation until the coach supplies a value.
  return {
    ...state,
    workout: writeField(state.workout, issue.path, emptyValueFor(issue.path)),
    issues: { ...state.issues, [issue.id]: "rejected" },
  };
}

export function undoIssue(state: ReviewState, issue: AnalysisIssue): ReviewState {
  const original = getAtPath(state.analysis.workout, issue.path);
  const issues = { ...state.issues };
  delete issues[issue.id];
  return { ...state, workout: writeField(state.workout, issue.path, original ?? emptyValueFor(issue.path)), issues };
}

export function addSuggestion(state: ReviewState, suggestion: AnalysisSuggestion, value: unknown): ReviewState {
  return {
    ...state,
    workout: writeField(state.workout, suggestion.path, value),
    suggestions: { ...state.suggestions, [suggestion.id]: "added" },
  };
}

export function dismissSuggestion(state: ReviewState, suggestion: AnalysisSuggestion): ReviewState {
  return { ...state, suggestions: { ...state.suggestions, [suggestion.id]: "dismissed" } };
}

export function openIssues(state: ReviewState) {
  return state.analysis.issues.filter((issue) => !state.issues[issue.id]);
}

export function openSuggestions(state: ReviewState) {
  return state.analysis.suggestions.filter((suggestion) => !state.suggestions[suggestion.id]);
}

/**
 * Everything that would make creation fail: required canonical fields with no
 * value (including ones the coach rejected) and an invalid title or type.
 */
export function blockingProblems(title: string, type: string, state: ReviewState | null): BlockingProblem[] {
  const problems: BlockingProblem[] = [];
  const trimmed = title.trim();

  if (!trimmed) problems.push({ path: "title", reason: "required" });
  else if (trimmed.length < 3) problems.push({ path: "title", reason: "too_short" });
  if (!WORKOUT_TYPES.includes(type)) problems.push({ path: "type", reason: "required" });
  if (!state) return problems;

  state.workout.sections.forEach((section, sectionIndex) => {
    if (isEmptyValue(section.name)) problems.push({ path: `sections.${sectionIndex}.name`, reason: "required" });
    section.exercises.forEach((exercise, exerciseIndex) => {
      if (isEmptyValue(exercise.name)) {
        problems.push({ path: `sections.${sectionIndex}.exercises.${exerciseIndex}.name`, reason: "required" });
      }
    });
  });

  return problems;
}

/** Canonical fields sent on publish; null and empty values are omitted. */
export function publishFields(state: ReviewState | null) {
  if (!state) return { sections: [] as CanonicalSection[] };
  const { workout } = state;

  return {
    subtitle: workout.subtitle ?? null,
    description: workout.description ?? null,
    difficulty: workout.difficulty ?? null,
    estimated_duration_seconds: workout.estimated_duration_seconds ?? null,
    equipment: workout.equipment ?? [],
    tags: workout.tags ?? [],
    workout_metadata: { timer_inference: timerInference(state) },
    sections: workout.sections.map((section) => ({
      ...compact(section),
      exercises: section.exercises.map((exercise) => compact(exercise)),
    })),
  };
}

const TIMER_ISSUE_CODES = new Set(["invalid_timer", "unknown_format"]);

/**
 * "incomplete" when a section timer the assistant could not infer is still
 * unresolved; execution then falls back to the manual timer. Rejecting the
 * timer issue means "no timer for this block", which is complete.
 */
export function timerInference(state: ReviewState): "complete" | "incomplete" {
  const unresolved = state.analysis.issues.some(
    (issue) => TIMER_ISSUE_CODES.has(issue.code) && state.issues[issue.id] !== "rejected",
  );
  return unresolved ? "incomplete" : "complete";
}

function compact<T extends Record<string, unknown>>(value: T) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => !isEmptyValue(entry))) as Partial<T>;
}

export type PathLabel = { section?: number; exercise?: number; field: string };

export function describePath(path: string): PathLabel {
  const parts = path.split(".");
  if (parts[0] !== "sections") return { field: path };
  const section = Number(parts[1]) + 1;
  if (parts[2] === "exercises") return { section, exercise: Number(parts[3]) + 1, field: parts[4] ?? "" };
  return { section, field: parts[2] ?? "" };
}

/** Parses free input for a canonical field; returns undefined when invalid. */
export function parseFieldInput(path: string, input: string): unknown {
  const field = fieldOf(path);
  const trimmed = input.trim();
  if (!trimmed) return undefined;

  if (LIST_FIELDS.has(field)) {
    const items = trimmed.split(",").map((item) => item.trim()).filter(Boolean);
    return items.length ? items : undefined;
  }

  if (["sets", "prescription_value", "load_value", "rest_seconds"].includes(field)) {
    const number = Number(trimmed.replace(",", "."));
    return Number.isFinite(number) && number >= 0 ? Math.round(number) : undefined;
  }

  if (field === "estimated_duration_seconds") {
    const minutes = Number(trimmed.replace(",", "."));
    return Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes * 60) : undefined;
  }

  if (field === "type") return WORKOUT_TYPES.includes(trimmed.toLowerCase()) ? trimmed.toLowerCase() : undefined;
  return trimmed;
}

export function formatFieldValue(path: string, value: unknown): string {
  if (isEmptyValue(value)) return "";
  if (Array.isArray(value)) return value.join(", ");
  if (fieldOf(path) === "estimated_duration_seconds" && typeof value === "number") return String(Math.round(value / 60));
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

/** Replaces the first verbatim occurrence of `find`; returns null when absent. */
export function replaceFirst(text: string, find: string, replace: string) {
  const index = text.indexOf(find);
  if (index < 0) return null;
  return text.slice(0, index) + replace + text.slice(index + find.length);
}
