import { sectionLetter } from "@/stores/workout-creation";
import { FORMAT_EXERCISE_CONTEXT, type DraftWorkoutState } from "@/types/workout";

import { rowKey, type GridCell } from "./grid";

type Translate = (key: string, values?: Record<string, string | number>) => string;

/** What still stops a structured workout from being published, each with the field that fixes it. */
export type PublishProblem = { message: string; cell: GridCell | null };

export function structuredProblems(
  state: Pick<DraftWorkoutState, "title" | "type" | "sections">,
  i18n: Translate,
): PublishProblem[] {
  const problems: PublishProblem[] = [];
  if (!state.title.trim()) problems.push({ message: i18n("missingWorkoutTitlebb8efa0"), cell: { rowKey: "w", col: "title" } });
  if (!state.type) problems.push({ message: i18n("missingWorkoutTypedd14f84"), cell: { rowKey: "w", col: "type" } });
  if (state.sections.length === 0) problems.push({ message: i18n("addAtLeastOneSectioncf462d3"), cell: null });

  state.sections.forEach((section, sectionIndex) => {
    const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
    const sectionLabel = section.name.trim() || sectionLetter(sectionIndex);
    const needsExercises = section.format !== "rest" && section.format !== "kcal_target";
    if (needsExercises && section.exercises.every((exercise) => exercise.itemType === "header")) {
      problems.push({
        message: i18n("value0AddAtLeastOneExercise3ce2e7a", { value0: sectionLabel }),
        cell: { rowKey: rowKey({ kind: "section", sectionId: section.localId }), col: "name" },
      });
    }

    section.exercises.forEach((exercise, exerciseIndex) => {
      const key = rowKey({ kind: "exercise", sectionId: section.localId, exerciseId: exercise.localId });
      const exerciseLabel = exercise.name.trim() || i18n("exerciseValue08ca6dce", { value0: exerciseIndex + 1 });
      if (!exercise.name.trim()) {
        problems.push({
          message: i18n("value0Value1NeedsANamedc0e3ad", { value0: sectionLabel, value1: exerciseLabel }),
          cell: { rowKey: key, col: "name" },
        });
      }
      if (exercise.itemType === "header") return;
      if (ctx.showSets && exercise.sets <= 0) {
        problems.push({
          message: i18n("value0Value1NeedsSets042ee99", { value0: sectionLabel, value1: exerciseLabel }),
          cell: { rowKey: key, col: "sets" },
        });
      }
      if (ctx.showPrescription && !ctx.prescriptionHint && !ctx.ladderPrescription && exercise.prescriptionValue <= 0) {
        problems.push({
          message: i18n("value0Value1NeedsAPrescription96c7234", { value0: sectionLabel, value1: exerciseLabel }),
          cell: { rowKey: key, col: "rx" },
        });
      }
    });
  });
  return problems;
}
