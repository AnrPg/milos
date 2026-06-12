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
  return segment.exercises
    .filter((exercise) => !exercise.excluded)
    .flatMap((exercise) => {
      const setCount = exercise.sets && exercise.sets > 1 ? exercise.sets : 1;

      return Array.from({ length: setCount }, (_, index) =>
        buildStepId(segment, exercise, setCount, index + 1),
      );
    });
}

export function isRepeatableSegment(segment: TimerSegment) {
  return [
    "amrap",
    "edt",
    "death_by",
    "ladder_ascending",
    "ladder_descending",
    "pyramid",
  ].includes(segment.format);
}

export function shouldAutoAdvanceOnChecklistComplete(segment: TimerSegment) {
  if (isRepeatableSegment(segment)) {
    return false;
  }

  return segment.kind === "countup" || segment.kind === "manual" || segment.kind === "no_timer";
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
      const scoringMode = String(segment.timer_config?.scoring_mode ?? "amrap");

      if (scoringMode === "for_time") {
        const elapsed = effectiveSectionElapsedMs(segment, state);
        return elapsed > 0
          ? {
              section_id: segment.section_id,
              value: formatDurationMs(elapsed),
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
  return segment.exercises
    .filter((exercise) => !exercise.excluded)
    .flatMap((exercise) => {
      const setCount = exercise.sets && exercise.sets > 1 ? exercise.sets : 1;
      const reps = exercise.prescription_value ?? 1;

      return Array.from({ length: setCount }, (_, index) => ({
        stepId: buildStepId(segment, exercise, setCount, index + 1),
        reps,
      }));
    });
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
