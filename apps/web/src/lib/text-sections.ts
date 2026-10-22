import type { JSONContent } from "@tiptap/react";

import { type FreeTextTimerPreset, parseFreeTextTimerPreset } from "@/lib/free-text-timer";

/**
 * Workouts written without the assistant (ADR-180) are a list of text
 * sections, each with the timer the coach picked for it. The athlete runs
 * those timers one section at a time.
 */
export const SECTIONED_TEXT_MODE = "sectioned_text";

export type TextSection = {
  id: string;
  /** The coach's title; empty when the section has none. */
  title: string;
  body: string;
  preset: FreeTextTimerPreset | null;
  /** What the section is scored by (empty: not scored). */
  metrics: SectionMetric[];
};

export type TextSectionSource = {
  id?: string | null;
  name?: string | null;
  free_text_body?: string | null;
  timer_preset?: unknown;
  score_config?: unknown;
  section_metadata?: Record<string, unknown> | null;
};

/**
 * What a section can be scored by («This section is scored by»), mirroring
 * the API's `SectionScoring`: the common paradigms plus `custom` (a plain
 * number). Every result is a number; time is in seconds.
 */
export const SCORE_KINDS = ["rounds", "reps", "time", "load", "calories", "distance", "custom"] as const;
export type ScoreKind = (typeof SCORE_KINDS)[number];

export const SCORE_KIND_UNITS: Record<ScoreKind, string | null> = {
  rounds: "rounds",
  reps: "reps",
  time: "s",
  load: "kg",
  calories: "kcal",
  distance: "m",
  custom: null,
};

export const MAX_SECTION_METRICS = 6;
export const MAX_METRIC_LABEL_LENGTH = 40;

export type SectionMetric = {
  /** Set by the API from the label; the client derives the same for checks. */
  key: string;
  label: string;
  kind: ScoreKind;
};

/** The API's metric key: a slug of the coach's label (the kind when the label has no letters). */
export function metricKey(label: string, kind: ScoreKind): string {
  const slug = label
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
  return slug || kind;
}

export function readMetrics(scoreConfig: unknown): SectionMetric[] {
  const metrics = (scoreConfig as { metrics?: unknown } | null | undefined)?.metrics;
  if (!Array.isArray(metrics)) return [];
  return metrics.flatMap((raw) => {
    const metric = raw as { key?: unknown; label?: unknown; kind?: unknown };
    if (typeof metric?.label !== "string" || !metric.label.trim()) return [];
    const kind = SCORE_KINDS.includes(metric.kind as ScoreKind) ? (metric.kind as ScoreKind) : "custom";
    const key = typeof metric.key === "string" && metric.key ? metric.key : metricKey(metric.label, kind);
    return [{ key, label: metric.label.trim(), kind }];
  });
}

/** Words that say what a typed scoring name counts, in the languages coaches write in. */
const KIND_HINTS: Record<Exclude<ScoreKind, "custom">, string[]> = {
  rounds: ["round", "rounds", "rds", "rnd", "γύρ", "rund", "ronda", "tour", "giri", "rondes", "voltas", "раунд", "кръг", "جول", "סבב"],
  reps: ["rep", "reps", "repetition", "επαν", "wdh", "wiederholung", "repetici", "répétition", "ripetizion", "herhaling", "повтор", "تكرار", "חזר"],
  time: ["time", "χρόν", "zeit", "tiempo", "temps", "tempo", "tijd", "время", "врем", "وقت", "זמן", "mm:ss"],
  load: ["load", "weight", "kg", "lb", "βάρος", "φορτ", "gewicht", "peso", "poids", "carico", "вес", "тегло", "وزن", "משקל"],
  calories: ["cal", "kcal", "θερμ", "kalor", "calor", "калор", "سعر", "קלור"],
  distance: ["distance", "meter", "metre", "km", "απόστ", "μέτρ", "distanz", "distancia", "afstand", "дистанц", "разстоя", "مساف", "מרחק"],
};

const fold = (text: string) =>
  text
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .trim();

/** The kind a typed scoring name most likely counts («Thrusters» counts reps). */
export function inferScoreKind(label: string, kindLabels: Record<ScoreKind, string>): ScoreKind {
  const text = fold(label);
  if (!text) return "reps";
  for (const kind of SCORE_KINDS) {
    if (kind === "custom") continue;
    if (fold(kindLabels[kind]) === text) return kind;
    if (KIND_HINTS[kind].some((hint) => text.split(/[^\p{L}\p{N}:]+/u).some((word) => word.startsWith(fold(hint))))) return kind;
  }
  return "reps";
}

/**
 * Fuzzy live suggestions for the «scored by» field: the common paradigms
 * whose name (or a hint word) matches what the coach typed, best first —
 * prefix, then substring, then letters in order.
 */
export function suggestScoreKinds(query: string, kindLabels: Record<ScoreKind, string>, taken: SectionMetric[] = []): ScoreKind[] {
  const text = fold(query);
  const takenKinds = new Set(taken.map((metric) => metric.kind));
  const rank = (kind: ScoreKind) => {
    if (!text) return 1;
    const names = [fold(kindLabels[kind]), kind, ...(kind === "custom" ? [] : KIND_HINTS[kind].map(fold))];
    let best = Infinity;
    for (const name of names) {
      if (name.startsWith(text) || text.startsWith(name)) best = Math.min(best, 0);
      else if (name.includes(text)) best = Math.min(best, 1);
      else if (isSubsequence(text, name)) best = Math.min(best, 2);
    }
    return best;
  };
  return SCORE_KINDS.filter((kind) => kind !== "custom")
    .map((kind) => ({ kind, rank: rank(kind) + (takenKinds.has(kind) ? 0.5 : 0) }))
    .filter((entry) => Number.isFinite(entry.rank))
    .sort((a, b) => a.rank - b.rank)
    .map((entry) => entry.kind);
}

function isSubsequence(needle: string, haystack: string) {
  let at = 0;
  for (const char of haystack) if (char === needle[at]) at += 1;
  return at === needle.length;
}

/** The text sections of a sectioned workout, in order; [] for any other workout. */
export function readTextSections(workout: {
  authoring_mode?: string | null;
  sections?: TextSectionSource[] | null;
} | null | undefined): TextSection[] {
  if (!workout || workout.authoring_mode !== SECTIONED_TEXT_MODE) return [];
  return (workout.sections ?? []).map((section, index) => ({
    id: section.id ?? `text-section-${index}`,
    title: section.section_metadata?.untitled === true ? "" : (section.name ?? "").trim(),
    body: section.free_text_body ?? "",
    preset: parseFreeTextTimerPreset(section.timer_preset),
    metrics: readMetrics(section.score_config),
  }));
}

const clock = (seconds: number | null | undefined) => {
  if (!seconds || seconds <= 0) return null;
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
};

/**
 * A short, language-neutral summary of a timer next to its format name, e.g.
 * «AMRAP · 12:00», «EMOM · 10 × 1:00», «Tabata · 8 × 0:20/0:10».
 */
export function describePreset(preset: FreeTextTimerPreset, formatLabel: string): string {
  const parts: (string | null)[] = (() => {
    switch (preset.format) {
      case "amrap":
        return [clock(preset.duration_seconds ?? 720)];
      case "for_time":
        return [preset.duration_seconds ? `≤ ${clock(preset.duration_seconds)}` : null];
      case "emom":
        return [`${preset.rounds ?? 10} × ${clock(preset.interval_seconds ?? 60)}`];
      case "death_by":
        return [preset.rounds ? `${preset.rounds} × ${clock(preset.interval_seconds ?? 60)}` : clock(preset.interval_seconds ?? 60)];
      case "tabata":
      case "custom_hiit": {
        const rest = clock(preset.rest_seconds ?? (preset.format === "tabata" ? 10 : null));
        return [`${preset.rounds ?? 8} × ${clock(preset.work_seconds ?? 20)}${rest ? `/${rest}` : ""}`];
      }
      default:
        return [];
    }
  })();
  return [formatLabel, ...parts.filter(Boolean)].join(" · ");
}

/** Where an athlete is in a sectioned workout: the current section and the time each finished one took. */
export type SectionProgress = { index: number; banked: number[] };

const PROGRESS_KEY = "palee:text-sections:";

export function readSectionProgress(executionId: string): SectionProgress {
  try {
    const raw = JSON.parse(window.localStorage.getItem(PROGRESS_KEY + executionId) ?? "null") as Partial<SectionProgress> | null;
    const index = typeof raw?.index === "number" && raw.index >= 0 ? Math.floor(raw.index) : 0;
    const banked = Array.isArray(raw?.banked)
      ? raw.banked.map((value) => (typeof value === "number" && value >= 0 ? value : 0))
      : [];
    return { index, banked };
  } catch {
    return { index: 0, banked: [] };
  }
}

export function storeSectionProgress(executionId: string, progress: SectionProgress | null) {
  try {
    if (progress) window.localStorage.setItem(PROGRESS_KEY + executionId, JSON.stringify(progress));
    else window.localStorage.removeItem(PROGRESS_KEY + executionId);
  } catch {
    // Storage unavailable (private mode); progress still works for this visit.
  }
}

/** A section while the coach edits it; `key` is local, stable across reorders. */
export type EditorTextSection = {
  key: string;
  title: string;
  body: string;
  document: JSONContent;
  preset: FreeTextTimerPreset | null;
  metrics: SectionMetric[];
};

/** Why a section cannot be published yet (same codes the API answers with). */
export type SectionProblem = {
  section: number | null;
  problem: "text_required" | "text_too_long" | "title_too_long" | "timer_required" | "too_many_sections" | "scoring_invalid" | string;
};

export const MAX_TEXT_SECTIONS = 30;
const MAX_SECTION_BODY_BYTES = 20_000;

let sectionKeySeed = 0;
const sectionKey = () => `section-${Date.now().toString(36)}-${(sectionKeySeed += 1)}`;

export function emptyDocument(): JSONContent {
  return { type: "doc", content: [{ type: "paragraph" }] };
}

export function textToDocument(source: string): JSONContent {
  return {
    type: "doc",
    content: source.split("\n").map((line) => ({
      type: "paragraph",
      ...(line ? { content: [{ type: "text", text: line }] } : {}),
    })),
  };
}

export function emptySection(): EditorTextSection {
  return { key: sectionKey(), title: "", body: "", document: emptyDocument(), preset: null, metrics: [] };
}

const isDocument = (value: unknown): value is JSONContent =>
  Boolean(value) && typeof value === "object" && (value as { type?: unknown }).type === "doc";

/**
 * The editor's sections for a workout: its own text sections, or, for a
 * workout written as one free text, that text as section 1 with the
 * workout's timer (switching off the assistant never loses what was written).
 */
export function editorSectionsFrom(
  workout: { authoring_mode?: string | null; sections?: TextSectionSource[] | null; free_text_body?: string | null; free_text_document?: Record<string, unknown> | null },
  wholeWorkoutPreset: FreeTextTimerPreset | null,
): EditorTextSection[] {
  if (workout.authoring_mode === SECTIONED_TEXT_MODE && (workout.sections?.length ?? 0) > 0) {
    return (workout.sections ?? []).map((section) => {
      const raw = section as TextSectionSource & { free_text_document?: unknown };
      const body = raw.free_text_body ?? "";
      return {
        key: sectionKey(),
        title: raw.section_metadata?.untitled === true ? "" : (raw.name ?? ""),
        body,
        document: isDocument(raw.free_text_document) ? raw.free_text_document : textToDocument(body),
        preset: parseFreeTextTimerPreset(raw.timer_preset),
        metrics: readMetrics(raw.score_config),
      };
    });
  }

  const body = workout.free_text_body ?? "";
  if (!body.trim()) return [{ ...emptySection(), preset: wholeWorkoutPreset }];
  return [
    {
      key: sectionKey(),
      title: "",
      body,
      document: isDocument(workout.free_text_document) ? workout.free_text_document : textToDocument(body),
      preset: wholeWorkoutPreset,
      metrics: [],
    },
  ];
}

/**
 * One free text from text sections (switching the assistant back on): each
 * titled section becomes a heading above its own blocks. Timers are dropped,
 * since the assistant reads them from the text.
 */
export function sectionsToFreeText(sections: EditorTextSection[] | TextSection[]): { body: string; document: JSONContent } {
  const items = sections.map((section) => ({
    title: section.title.trim(),
    body: section.body,
    document: "document" in section ? section.document : textToDocument(section.body),
  }));
  return {
    body: items.map((item) => (item.title ? `${item.title}\n${item.body}` : item.body)).join("\n\n"),
    document: {
      type: "doc",
      content: items.flatMap((item) => [
        ...(item.title ? [{ type: "heading", attrs: { level: 3 }, content: [{ type: "text", text: item.title }] }] : []),
        ...(item.document.content ?? []),
      ]),
    },
  };
}

/** The sections as the API stores them. */
export function sectionsPayload(sections: EditorTextSection[]) {
  return sections.map((section, index) => ({
    name: section.title.trim(),
    order: index + 1,
    exercises: [],
    free_text_body: section.body.trim(),
    free_text_document: section.document,
    timer_preset: section.preset,
    score_config: section.metrics.length
      ? { metrics: section.metrics.map((metric) => ({ label: metric.label.trim(), kind: metric.kind })) }
      : null,
  }));
}

/** The same publish rules the API applies, checked before the round trip. */
export function sectionProblems(sections: EditorTextSection[]): SectionProblem[] {
  if (sections.length > MAX_TEXT_SECTIONS) return [{ section: null, problem: "too_many_sections" }];
  const encoder = new TextEncoder();
  return sections.flatMap((section, index) => {
    const number = index + 1;
    const body = section.body.trim();
    const problems: SectionProblem[] = [];
    if (!body) problems.push({ section: number, problem: "text_required" });
    if (encoder.encode(body).length > MAX_SECTION_BODY_BYTES) problems.push({ section: number, problem: "text_too_long" });
    if (section.title.trim().length > 120) problems.push({ section: number, problem: "title_too_long" });
    if (!section.preset) problems.push({ section: number, problem: "timer_required" });
    const keys = section.metrics.map((metric) => metricKey(metric.label, metric.kind));
    if (
      section.metrics.length > MAX_SECTION_METRICS ||
      new Set(keys).size !== keys.length ||
      section.metrics.some((metric) => !metric.label.trim() || metric.label.trim().length > MAX_METRIC_LABEL_LENGTH)
    )
      problems.push({ section: number, problem: "scoring_invalid" });
    return problems;
  });
}

/** An athlete's result for one metric of a text section, as the API takes it. */
export type TextSectionResult = { section_id: string; metric_key: string; value: number };

/** «m:ss», «mm:ss» or «h:mm:ss» (or plain seconds) to seconds; null when not a time. */
export function parseDuration(text: string): number | null {
  const parts = text.trim().split(":");
  if (parts.length > 3 || parts.some((part) => !/^\d+$/.test(part))) return null;
  return parts.reduce((total, part) => total * 60 + Number(part), 0);
}

/** A result field's text to the number the API stores; null when blank or not a number. */
export function parseMetricValue(text: string, kind: ScoreKind): number | null {
  const trimmed = text.trim();
  if (!trimmed) return null;
  if (kind === "time") return parseDuration(trimmed);
  const number = Number(trimmed.replace(",", "."));
  return Number.isFinite(number) && number >= 0 ? number : null;
}
