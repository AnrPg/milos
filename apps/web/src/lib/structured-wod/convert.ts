import type { FreeTextTimerPreset } from "@/lib/free-text-timer";
import { textToDocument, type EditorTextSection } from "@/lib/text-sections";
import { parseDraftSections, sectionLetter } from "@/stores/workout-creation";
import {
  FORMAT_EXERCISE_CONTEXT,
  makeDefaultFormatParams,
  makeDefaultSection,
  type DraftExercise,
  type DraftSection,
  type FormatParams,
  type SectionFormat,
} from "@/types/workout";

import { formatLoad, formatPrescription } from "./quantity";

/**
 * ADR-231: switching a workout between text and structured never loses what
 * was written. Structured → text writes each section as lines a coach would
 * put on the whiteboard («3 × 10 Back Squat @ 70%») with its timer; text →
 * structured (without the assistant) keeps each text section's title and
 * timer and puts its text in the section's note, to be turned into rows.
 */

type WorkoutLike = {
  authoring_mode?: string | null;
  sections?: unknown[] | null;
  draft_data?: unknown;
};

export const STRUCTURED_MODE = "structured";

/** The structured sections a stored workout holds (its draft first, then what was published). */
export function storedStructuredSections(workout: WorkoutLike): DraftSection[] {
  const draft = workout.draft_data as { sections?: unknown } | null | undefined;
  if (Array.isArray(draft?.sections) && draft.sections.length > 0) return parseDraftSections(draft.sections);
  return parseDraftSections(workout.sections ?? []);
}

/** Whether a stored workout is structured and has something written in it. */
export function hasStructuredContent(workout: WorkoutLike | null | undefined): boolean {
  if (!workout || (workout.authoring_mode ?? STRUCTURED_MODE) !== STRUCTURED_MODE) return false;
  return storedStructuredSections(workout).some((section) => section.exercises.length > 0 || Boolean(section.note?.trim()));
}

function exerciseLine(exercise: DraftExercise, section: DraftSection, bodyweightLabel: string): string {
  const name = exercise.name.trim();
  if (exercise.itemType === "header") return name;
  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
  const amount = ctx.showPrescription ? formatPrescription(exercise.prescriptionValue, exercise.prescriptionUnit) : "";
  const step = ctx.ladderPrescription && exercise.prescriptionStep ? ` (+${exercise.prescriptionStep})` : "";
  const sets = ctx.showSets && exercise.sets > 0 ? `${exercise.sets} × ` : "";
  const load = ctx.showLoad ? formatLoad(exercise.loadMode, exercise.loadValue, bodyweightLabel) : "";
  const main = [`${sets}${amount}${step}`.trim(), name].filter(Boolean).join(" ");
  const lines = [load ? `${main} @ ${load}` : main];
  if (exercise.note?.trim()) lines.push(`  ${exercise.note.trim()}`);
  return lines.join("\n");
}

/** The timer of a text section closest to a structured section's format. */
export function presetForSection(section: DraftSection): FreeTextTimerPreset {
  const p = section.formatParams;
  const number = (key: string) => (typeof p[key] === "number" && (p[key] as number) > 0 ? (p[key] as number) : null);
  switch (section.format) {
    case "amrap":
      return { format: "amrap", duration_seconds: number("duration_seconds") };
    case "for_time":
      return { format: "for_time", duration_seconds: number("time_cap_seconds") };
    case "emom":
    case "complex_emom":
    case "even_odd": {
      const interval = number("interval_seconds") ?? 60;
      const duration = number("duration_seconds");
      return { format: "emom", interval_seconds: interval, rounds: duration ? Math.max(1, Math.round(duration / interval)) : null };
    }
    case "tabata":
    case "custom_hiit":
      return { format: section.format, work_seconds: number("work_seconds"), rest_seconds: number("rest_seconds"), rounds: number("rounds") };
    case "death_by":
      return { format: "death_by", interval_seconds: number("interval_seconds"), rounds: number("ladder_cap") };
    default:
      return { format: "untimed" };
  }
}

/** A text section's timer as a structured section's format and fields. */
export function sectionFormatForPreset(preset: FreeTextTimerPreset | null): { format: SectionFormat; params: FormatParams } {
  if (!preset) return { format: "untimed", params: {} };
  const params = (format: SectionFormat, values: FormatParams) => ({
    format,
    params: { ...makeDefaultFormatParams(format), ...Object.fromEntries(Object.entries(values).filter(([, value]) => value != null && value > 0)) },
  });
  switch (preset.format) {
    case "amrap":
      return params("amrap", { duration_seconds: preset.duration_seconds ?? null });
    case "for_time":
      return params("for_time", { time_cap_seconds: preset.duration_seconds ?? null });
    case "emom": {
      const interval = preset.interval_seconds ?? 60;
      return params("emom", { interval_seconds: interval, duration_seconds: preset.rounds ? preset.rounds * interval : null });
    }
    case "tabata":
    case "custom_hiit":
      return params(preset.format, { work_seconds: preset.work_seconds ?? null, rest_seconds: preset.rest_seconds ?? null, rounds: preset.rounds ?? null });
    case "death_by":
      return params("death_by", { interval_seconds: preset.interval_seconds ?? null, ladder_cap: preset.rounds ?? null });
    default:
      return { format: "untimed", params: {} };
  }
}

let keySeed = 0;

/** Structured sections as text sections (each with its own timer). */
export function structuredToTextSections(sections: DraftSection[], bodyweightLabel: string): EditorTextSection[] {
  return sections.map((section, index) => {
    const lines = [
      ...(section.note?.trim() ? [section.note.trim()] : []),
      ...section.exercises.map((exercise) => exerciseLine(exercise, section, bodyweightLabel)).filter(Boolean),
    ];
    const body = lines.join("\n");
    keySeed += 1;
    return {
      key: `structured-${keySeed}`,
      title: section.name.trim() || sectionLetter(index),
      body,
      document: textToDocument(body),
      preset: presetForSection(section),
      metrics: [],
    };
  });
}

/** Text sections as structured sections: title and timer kept, the text in the note. */
export function textToStructuredSections(sections: Array<Pick<EditorTextSection, "title" | "body" | "preset">>): DraftSection[] {
  return sections
    .filter((section) => section.title.trim() || section.body.trim())
    .map((source) => {
      const { format, params } = sectionFormatForPreset(source.preset);
      return {
        ...makeDefaultSection(),
        name: source.title.trim(),
        format,
        formatParams: params,
        note: source.body.trim() || null,
      };
    });
}
