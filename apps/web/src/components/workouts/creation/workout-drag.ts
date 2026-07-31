export type WorkoutDragData =
  | { type: "section" }
  | { type: "exercise"; sectionId: string };

type ResolveWorkoutDragEndInput = {
  activeId: string;
  activeData: unknown;
  dragStartData: WorkoutDragData | null;
  overId: string;
  overData: unknown;
};

export type WorkoutDragOperation =
  | { type: "none" }
  | { type: "reorder-section"; fromSectionId: string; toSectionId: string }
  | { type: "reorder-exercise"; sectionId: string; fromExerciseId: string; toExerciseId: string }
  | { type: "move-exercise"; exerciseId: string; fromSectionId: string; toSectionId: string };

export function resolveWorkoutDragEnd({
  activeId,
  activeData,
  dragStartData,
  overId,
  overData,
}: ResolveWorkoutDragEndInput): WorkoutDragOperation {
  const source = isWorkoutDragData(activeData) ? activeData : dragStartData;
  const target = isWorkoutDragData(overData) ? overData : null;

  if (!source || !target || activeId === overId) return { type: "none" };

  if (source.type === "section") {
    return target.type === "section"
      ? { type: "reorder-section", fromSectionId: activeId, toSectionId: overId }
      : { type: "none" };
  }

  if (target.type === "section") {
    return source.sectionId === overId
      ? { type: "none" }
      : {
          type: "move-exercise",
          exerciseId: activeId,
          fromSectionId: source.sectionId,
          toSectionId: overId,
        };
  }

  if (source.sectionId === target.sectionId) {
    return {
      type: "reorder-exercise",
      sectionId: source.sectionId,
      fromExerciseId: activeId,
      toExerciseId: overId,
    };
  }

  return {
    type: "move-exercise",
    exerciseId: activeId,
    fromSectionId: source.sectionId,
    toSectionId: target.sectionId,
  };
}

function isWorkoutDragData(value: unknown): value is WorkoutDragData {
  if (!value || typeof value !== "object") return false;
  const data = value as Record<string, unknown>;

  return (
    data.type === "section" ||
    (data.type === "exercise" && typeof data.sectionId === "string")
  );
}
