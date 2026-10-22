import type { JSONContent } from "@tiptap/react";

import { type FreeTextTimerPreset, parseFreeTextTimerPreset } from "@/lib/free-text-timer";

/**
 * Workouts written without the assistant (ADR-179) are a list of text
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
};

export type TextSectionSource = {
  id?: string | null;
  name?: string | null;
  free_text_body?: string | null;
  timer_preset?: unknown;
  section_metadata?: Record<string, unknown> | null;
};

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
};

/** Why a section cannot be published yet (same codes the API answers with). */
export type SectionProblem = {
  section: number | null;
  problem: "text_required" | "text_too_long" | "title_too_long" | "timer_required" | "too_many_sections" | string;
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
  return { key: sectionKey(), title: "", body: "", document: emptyDocument(), preset: null };
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
    return problems;
  });
}
