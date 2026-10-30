"use client";

import type { SectionScore, TimerSegment } from "@/api/executions";

type ProgressState = {
  checkedExerciseIds: string[];
  sectionElapsedMs: Record<string, number>;
  segmentCycleCounts: Record<string, number>;
  currentSegment?: TimerSegment | null;
  currentElapsedMs?: number;
};

export function buildStepId(
  segment: TimerSegment,
  exercise: TimerSegment["exercises"][number],
  setCount: number,
  setNumber: number,
) {
  if (setCount === 1) {
    return `${segment.segment_key}::${exercise.id}`;
  }

  return `${segment.segment_key}::${exercise.id}::set:${setNumber}`;
}

export function buildSegmentStepIds(segment: TimerSegment) {
  return buildSegmentStepDefinitions(segment).map((step) => step.stepId);
}

export type SegmentStepDefinition = {
  stepId: string;
  exercise: TimerSegment["exercises"][number];
  setNumber: number;
  setCount: number;
  setPrescription: NonNullable<TimerSegment["exercises"][number]["set_prescriptions"]>[number] | null;
  groupKind: "superset" | "alternating" | null;
  groupId: string | null;
};

export function buildSegmentStepDefinitions(segment: TimerSegment): SegmentStepDefinition[] {
  const exercises = segment.exercises.filter(
    (exercise) => !exercise.excluded && exercise.item_type !== "header",
  );
  const consumedGroups = new Set<string>();
  const steps: SegmentStepDefinition[] = [];

  for (const exercise of exercises) {
    const groupKind = exercise.superset_group_id
      ? "superset"
      : exercise.alternating_group_id
        ? "alternating"
        : null;
    const groupId = exercise.superset_group_id ?? exercise.alternating_group_id ?? null;

    if (groupKind && groupId) {
      if (consumedGroups.has(groupId)) continue;
      consumedGroups.add(groupId);
      const members = exercises.filter((candidate) =>
        groupKind === "superset"
          ? candidate.superset_group_id === groupId
          : candidate.alternating_group_id === groupId,
      );
      const maxSets = Math.max(...members.map(exerciseSetCount));

      for (let setNumber = 1; setNumber <= maxSets; setNumber += 1) {
        for (const member of members) {
          const setCount = exerciseSetCount(member);
          if (setNumber > setCount) continue;
          steps.push(stepDefinition(segment, member, setNumber, setCount, groupKind, groupId));
        }
      }

      continue;
    }

    const setCount = exerciseSetCount(exercise);
    for (let setNumber = 1; setNumber <= setCount; setNumber += 1) {
      steps.push(stepDefinition(segment, exercise, setNumber, setCount, null, null));
    }
  }

  return steps;
}

function stepDefinition(
  segment: TimerSegment,
  exercise: TimerSegment["exercises"][number],
  setNumber: number,
  setCount: number,
  groupKind: SegmentStepDefinition["groupKind"],
  groupId: string | null,
): SegmentStepDefinition {
  return {
    stepId: buildStepId(segment, exercise, setCount, setNumber),
    exercise,
    setNumber,
    setCount,
    setPrescription:
      exercise.set_prescriptions?.find((set) => set.set_index === setNumber) ?? null,
    groupKind,
    groupId,
  };
}

function exerciseSetCount(exercise: TimerSegment["exercises"][number]) {
  if (exercise.set_prescriptions && exercise.set_prescriptions.length > 0) {
    return exercise.set_prescriptions.length;
  }
  return exercise.sets && exercise.sets > 1 ? exercise.sets : 1;
}

const ROUND_COUNTING_FORMATS = [
  "amrap",
  "edt",
  "death_by",
  "ladder_ascending",
  "ladder_descending",
  "pyramid",
];

/**
 * Segments where the athlete repeats the same list and counts rounds: AMRAP
 * style formats, ladders, open-ended interval cycles (Death By, EMOM to
 * failure) and "N rounds for time".
 */
export function isRepeatableSegment(segment: TimerSegment) {
  return (
    ROUND_COUNTING_FORMATS.includes(segment.format) ||
    segment.kind === "interval_cycle" ||
    roundTarget(segment) !== null
  );
}

/** Rounds to complete before the segment is done ("5 rounds for time"). */
export function roundTarget(segment: TimerSegment) {
  return segment.format === "for_time" && segment.total_rounds && segment.total_rounds > 1
    ? segment.total_rounds
    : null;
}

export function shouldAutoAdvanceOnChecklistComplete(segment: TimerSegment) {
  if (isRepeatableSegment(segment)) {
    return false;
  }

  return segment.kind === "countup" || segment.kind === "manual" || segment.kind === "no_timer";
}

/**
 * Exercises of an interval cycle shown in a given window. Exercises assigned to
 * minute N of a rotation repeat every rotation (the authored interval pattern
 * length, else the highest assignment); unassigned ones appear every window.
 */
export function stepsForWindow(segment: TimerSegment, windowIndex: number | null) {
  const inWindow = exerciseInWindow(segment, windowIndex);
  return buildSegmentStepDefinitions(segment).filter((step) => inWindow(step.exercise));
}

/**
 * Whether an exercise of an interval cycle is done in window `windowIndex`
 * (the rule of `stepsForWindow`); every exercise when the segment does not
 * rotate. The class timer's «Τώρα» panel shows the same exercises.
 */
export function exerciseInWindow(segment: TimerSegment, windowIndex: number | null) {
  const every = () => true;
  if (windowIndex === null || segment.kind !== "interval_cycle") return every;

  const pattern = segment.timer_config?.interval_pattern_seconds;
  const assignments = segment.exercises
    .map((exercise) => exercise.interval_assignment ?? 0)
    .filter((assignment) => assignment > 0);
  const rotation = Array.isArray(pattern) && pattern.length > 0 ? pattern.length : Math.max(0, ...assignments);
  if (rotation === 0) return every;

  const slot = ((windowIndex - 1) % rotation) + 1;
  return (exercise: TimerSegment["exercises"][number]) =>
    exercise.interval_assignment == null || exercise.interval_assignment === slot;
}

/** Reps each exercise targets in a round of a growing/shrinking format. */
export function targetRepsForRound(segment: TimerSegment, round: number) {
  return repsForRound(segment, round);
}

/**
 * Whether the segment at `index` is the last one emitted for its section.
 * Interval formats (Tabata, EMOM, Billat, Cluster…) split one section into many
 * segments; score capture belongs at the end of the section, not every interval.
 */
export function isLastSegmentOfSection(segments: TimerSegment[], index: number) {
  const segment = segments[index];
  if (!segment) return false;
  return segments[index + 1]?.section_id !== segment.section_id;
}

export function formatDurationMs(totalMs: number) {
  const totalSeconds = Math.max(0, Math.floor(totalMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function computeMeasuredScore(
  segment: TimerSegment,
  state: ProgressState,
): SectionScore | null {
  const checkedExerciseIds = state.checkedExerciseIds;
  const segmentCycleCounts = state.segmentCycleCounts;
  const segmentElapsedMs = effectiveSectionElapsedMs(segment, state);

  switch (segment.format) {
    case "emom":
    case "complex_emom": {
      const rawMode = segment.timer_config?.scoring_mode;
      const scoringMode = typeof rawMode === "string" && rawMode ? rawMode : "amrap";

      if (scoringMode === "for_time") {
        return segmentElapsedMs > 0
          ? {
              section_id: segment.section_id,
              value: formatDurationMs(segmentElapsedMs),
              score_type: "accumulated_work_time",
              kind: "final",
              source: "auto",
            }
          : null;
      }

      if (scoringMode === "for_quality") {
        return {
          section_id: segment.section_id,
          value: "Pass",
          score_type: "pass_fail",
          kind: "final",
          source: "auto",
        };
      }

      // amrap and to_failure require cross-window aggregation — backend handles it
      return null;
    }

    case "for_time":
    case "kcal_target":
    case "ladder_descending":
    case "pyramid":
    case "hrr":
      return segmentElapsedMs > 0
        ? {
            section_id: segment.section_id,
            value: formatDurationMs(segmentElapsedMs),
            score_type: "time",
            kind: "final",
            source: "auto",
          }
        : null;

    case "amrap": {
      const cycles = segmentCycleCounts[segment.segment_key] ?? 0;
      const partialReps = checkedReps(segment, checkedExerciseIds);
      return {
        section_id: segment.section_id,
        value: formatRoundsReps(cycles, partialReps),
        score_type: "rounds+reps",
        kind: "final",
        source: "auto",
      };
    }

    case "edt":
    case "train_to_exhaustion":
      return {
        section_id: segment.section_id,
        value:
          (segmentCycleCounts[segment.segment_key] ?? 0) * cycleReps(segment) +
          checkedReps(segment, checkedExerciseIds),
        unit: "reps",
        score_type: "reps",
        kind: "final",
        source: "auto",
      };

    case "death_by":
    case "ladder_ascending":
      return {
        section_id: segment.section_id,
        value: dynamicReps(segment, segmentCycleCounts[segment.segment_key] ?? 0, checkedExerciseIds),
        unit: "reps",
        score_type: "reps",
        kind: "final",
        source: "auto",
      };

    default:
      if (segment.score_config?.type === "time" && segmentElapsedMs > 0) {
        return {
          section_id: segment.section_id,
          value: formatDurationMs(segmentElapsedMs),
          score_type: "time",
          kind: "final",
          source: "auto",
        };
      }

      return null;
  }
}

function effectiveSectionElapsedMs(segment: TimerSegment, state: ProgressState) {
  const persisted = state.sectionElapsedMs[segment.section_id] ?? 0;

  if (state.currentSegment?.section_id === segment.section_id && typeof state.currentElapsedMs === "number") {
    return Math.max(persisted, persisted + Math.max(0, state.currentElapsedMs));
  }

  return persisted;
}

function checkedReps(segment: TimerSegment, checkedExerciseIds: string[]) {
  return stepDefinitions(segment)
    .filter((step) => checkedExerciseIds.includes(step.stepId))
    .reduce((sum, step) => sum + step.reps, 0);
}

function cycleReps(segment: TimerSegment) {
  return stepDefinitions(segment).reduce((sum, step) => sum + step.reps, 0);
}

function stepDefinitions(segment: TimerSegment) {
  return buildSegmentStepDefinitions(segment).map((step) => ({
    stepId: step.stepId,
    reps: step.setPrescription?.prescription_value ?? step.exercise.prescription_value ?? 1,
  }));
}

function dynamicReps(
  segment: TimerSegment,
  completedCycles: number,
  checkedExerciseIds: string[],
) {
  const stepCount = stepDefinitions(segment).length;
  const partialSteps = stepDefinitions(segment).filter((step) =>
    checkedExerciseIds.includes(step.stepId),
  ).length;

  let total = 0;

  for (let round = 1; round <= completedCycles; round += 1) {
    total += stepCount * repsForRound(segment, round);
  }

  total += partialSteps * repsForRound(segment, completedCycles + 1);
  return total;
}

function repsForRound(segment: TimerSegment, round: number) {
  const timerConfig = segment.timer_config ?? {};
  const start = Number(timerConfig.start_reps ?? 1);
  const step = Number(timerConfig.step_reps ?? 1);

  switch (segment.format) {
    case "death_by":
    case "ladder_ascending":
      return start + step * (round - 1);
    case "ladder_descending": {
      const min = Number(timerConfig.min_reps ?? 1);
      return Math.max(start - step * (round - 1), min);
    }
    case "pyramid": {
      const peak = Number(timerConfig.peak_reps ?? start);
      const ascending: number[] = [];

      for (let value = step; value <= peak; value += step) {
        ascending.push(value);
      }

      const full = [...ascending, ...ascending.slice(0, -1).reverse()];
      return full[Math.min(round - 1, full.length - 1)] ?? peak;
    }
    default:
      return start;
  }
}

function formatRoundsReps(rounds: number, reps: number) {
  if (rounds <= 0) return `${reps} reps`;
  if (reps <= 0) return `${rounds} rounds`;
  return `${rounds} rounds + ${reps} reps`;
}

/**
 * Seconds of rest to count down after checking off `stepId` in a straight-set
 * workout: the exercise's prescribed rest between sets, after every set but
 * the last. In a superset or alternating group the rest follows the group's
 * last member of that set, using the longest rest any member prescribes.
 * Timed and interval formats already schedule their own rests.
 */
export function setRestSeconds(segment: TimerSegment, stepId: string): number | null {
  if (segment.format !== "untimed" || segment.kind !== "no_timer") return null;

  const steps = buildSegmentStepDefinitions(segment);
  const index = steps.findIndex((step) => step.stepId === stepId);
  const step = steps[index];
  if (!step) return null;

  const sameBlock = (candidate: SegmentStepDefinition) =>
    step.groupId ? candidate.groupId === step.groupId : candidate.exercise.id === step.exercise.id;
  const block = steps.filter(sameBlock);
  const lastSetNumber = Math.max(...block.map((candidate) => candidate.setNumber));
  if (step.setNumber >= lastSetNumber) return null;

  // Rest only once the whole set of a group is done.
  const laterInSet = steps
    .slice(index + 1)
    .some((candidate) => sameBlock(candidate) && candidate.setNumber === step.setNumber);
  if (laterInSet) return null;

  const rest = Math.max(0, ...block.map((candidate) => candidate.exercise.rest_seconds ?? 0));
  return rest > 0 ? rest : null;
}
