import { planSectionText, type Translate } from "@/components/workouts/plan-view/plan-model";
import { isPlanSection, planExerciseCount, STRUCTURED_PLAN_MODE } from "@/components/workouts/plan-view/read";
import { newId, newSection, validateSection, type PlanIssue, type PlanSection } from "@/lib/structured-plan";
import { editorSectionsFrom, SECTIONED_TEXT_MODE, sectionsToFreeText, textToDocument } from "@/lib/text-sections";
import type { PlanEditorDocument, PlanEditorSection } from "@/stores/structured-plan";
import type { WorkoutType } from "@/types/workout";

/**
 * ADR-270: saving and loading workouts written in the structured plan
 * editor, and switching a workout between free text and structured without
 * losing what was written.
 */

/** Where the WOD's own note (above its sections) is kept. */
export const PLAN_NOTE_METADATA_KEY = "plan_note";

type StoredSection = { id?: string | null; name?: string | null; plan?: unknown; section_metadata?: Record<string, unknown> | null };
/** The fields of a stored workout (`WorkoutRecord`) these helpers read. */
type WorkoutLike = {
  authoring_mode?: string | null;
  title?: string | null;
  free_text_body?: string | null;
  workout_metadata?: Record<string, unknown> | null;
  draft_data?: unknown;
  sections?: StoredSection[] | null;
};

/** The sections a stored plan workout holds: its draft first, then what was published. */
function storedPlanSections(workout: WorkoutLike): StoredSection[] {
  const draft = (workout.draft_data as { sections?: unknown } | null | undefined)?.sections;
  if (Array.isArray(draft) && draft.some((section) => isPlanSection((section as StoredSection | null)?.plan))) return draft as StoredSection[];
  return workout.sections ?? [];
}

/** The text a text workout holds (free text, or its text sections as one text). */
export function textOfWorkout(workout: WorkoutLike): string {
  if (workout.authoring_mode === SECTIONED_TEXT_MODE) {
    return sectionsToFreeText(editorSectionsFrom(workout as Parameters<typeof editorSectionsFrom>[0], null)).body.trim();
  }
  if (workout.authoring_mode === "free_text" || !workout.authoring_mode) return (workout.free_text_body ?? "").trim();
  return "";
}

/**
 * What the plan editor opens with. A plan workout opens as written. Any other
 * workout starts an empty plan; text it holds is kept as the note of the
 * first section, so switching never loses it.
 */
export function planDocumentFrom(workout: WorkoutLike): PlanEditorDocument {
  const title = workout.title ?? "";
  const metadataNote = workout.workout_metadata?.[PLAN_NOTE_METADATA_KEY];
  const note = typeof metadataNote === "string" ? metadataNote : "";
  if (workout.authoring_mode === STRUCTURED_PLAN_MODE) {
    const sections = storedPlanSections(workout).flatMap((section): PlanEditorSection[] =>
      isPlanSection(section.plan)
        ? [{ id: section.id ?? newId(), name: section.section_metadata?.untitled === true ? "" : (section.name ?? ""), plan: section.plan }]
        : [],
    );
    return { title, note, sections };
  }
  const text = textOfWorkout(workout);
  return { title, note: "", sections: text ? [{ id: newId(), name: "", plan: { ...newSection("sets"), note: text } }] : [] };
}

/** Whether switching the plan away would drop something the coach wrote. */
export function planHasContent(doc: Pick<PlanEditorDocument, "note" | "sections">): boolean {
  return (
    Boolean(doc.note.trim()) ||
    doc.sections.some(
      (section) =>
        Boolean(section.name.trim()) ||
        planExerciseCount(section.plan) > 0 ||
        Boolean(section.plan.note?.trim()) ||
        Object.values(section.plan.levelNotes ?? {}).some((note) => note.trim()),
    )
  );
}

const sectionLetter = (index: number) => String.fromCharCode(65 + (index % 26));

/** The sections as the API stores them: each with its plan, no client-built exercises. */
export function planSectionsPayload(sections: PlanEditorSection[]) {
  return sections.map((section, index) => {
    const name = section.name.trim();
    return {
      name: name || sectionLetter(index),
      order: index + 1,
      plan: section.plan,
      section_metadata: name ? {} : { untitled: true },
    };
  });
}

/** Draft save / publish payload of a structured plan workout. */
export function planPayload(doc: PlanEditorDocument, type: WorkoutType | "", storedMetadata: Record<string, unknown>) {
  const metadata: Record<string, unknown> = { ...storedMetadata };
  if (doc.note.trim()) metadata[PLAN_NOTE_METADATA_KEY] = doc.note;
  else delete metadata[PLAN_NOTE_METADATA_KEY];
  const sections = planSectionsPayload(doc.sections);
  const workoutType = type || null;
  const fields = { title: doc.title, type: workoutType, authoring_mode: STRUCTURED_PLAN_MODE, workout_metadata: metadata, sections };
  return { ...fields, draft_data: { ...fields } };
}

export type PlanDraftPayload = ReturnType<typeof planPayload>;

/** A plan written out as text a coach can keep editing (switching back to free text). */
export function planToText(doc: Pick<PlanEditorDocument, "note" | "sections">, t: Translate, levelLabels?: Record<string, string>): string {
  return [doc.note.trim(), ...doc.sections.map((section) => planSectionText(section.name, section.plan, t, levelLabels))]
    .filter(Boolean)
    .join("\n\n");
}

/** Draft payload that turns the workout into free text holding `body` (the assistant's editor reads it). */
export function freeTextPayload(title: string, type: WorkoutType | "", body: string, storedMetadata: Record<string, unknown>) {
  const metadata: Record<string, unknown> = { ...storedMetadata };
  delete metadata[PLAN_NOTE_METADATA_KEY];
  const document = textToDocument(body);
  const fields = {
    title,
    type: type || null,
    authoring_mode: "free_text",
    free_text_body: body,
    free_text_document: document,
    workout_metadata: metadata,
  };
  return { ...fields, draft_data: { ...fields, free_text_review: null } };
}

export type PlanProblem = { section: number; issues: PlanIssue[] };

/** What stops a plan from being published, per section (1-based), before the round trip. */
export function planProblems(sections: PlanEditorSection[]): PlanProblem[] {
  return sections.flatMap((section, index) => {
    const issues = validateSection(section.plan);
    return issues.length > 0 ? [{ section: index + 1, issues }] : [];
  });
}

/** A plan with something to do: at least one exercise, or a rest section. */
export function planIsEmpty(sections: PlanEditorSection[]): boolean {
  return !sections.some((section) => section.plan.flow === "rest" || planExerciseCount(section.plan) > 0);
}

/** Seconds the timed sections take, for WOD goals; null when any section has no clock. */
export function planTimeDomain(sections: PlanEditorSection[], total: (plan: PlanSection) => number | null): number | null {
  let seconds = 0;
  for (const section of sections) {
    const length = total(section.plan);
    if (!length) return null;
    seconds += length;
  }
  return seconds > 0 ? seconds : null;
}
