/**
 * ADR-270: what the athlete did in a plan section, one record per set /
 * round of each exercise, prescribed next to actual, for planned-vs-done
 * progress and analytics. Keyed by the plan row id and its place in the run
 * (block, round, inner part, AMRAP window), so it joins back to the plan
 * (`sections[].plan`) without depending on materialised exercise rows.
 *
 * Sent with the execution's completion as `plan_actuals`; a set the
 * athlete did not log counts as done as prescribed (`logged: false`).
 */
import type { PlanSetActual } from "@/api/executions";

import type { RunState } from "./runner";
import type { RunLogs } from "./score";
import type { RunSequence, RunWork } from "./sequence";

export type { PlanSetActual };

/** "18", "22.5", "22,5" → number; anything else → null. */
export function decimal(text: string | undefined | null): number | null {
  const m = /^\s*(\d+(?:[.,]\d+)?)\s*(?:kg)?\s*$/i.exec(text ?? "");
  return m ? Number(m[1].replace(",", ".")) : null;
}

const repsOf = (dose: string): number | null => decimal(dose.replace(/\s*cal$/, ""));
const kgOf = (load: string): number | null => {
  const m = /^(\d+(?:\.\d+)?) kg$/.exec(load.trim());
  return m ? Number(m[1]) : null;
};

/** One record per done work step of the main run, in the order done. */
export function planActuals(seq: RunSequence, state: RunState, logs: RunLogs, sectionId: string): PlanSetActual[] {
  const where = new Map<string, { step: RunWork; phase: number }>();
  seq.phases.forEach((phase, p) => {
    for (const step of phase.steps) if (step.kind === "work") where.set(step.key, { step, phase: p });
  });
  return state.completed.flatMap((key) => {
    const found = where.get(key);
    if (!found) return [];
    const { step, phase } = found;
    const log = logs[key] ?? {};
    const prescribedReps = repsOf(step.values.dose);
    const prescribedKg = kgOf(step.values.load);
    const loggedReps = decimal(log.reps);
    const loggedKg = decimal(log.load);
    return [
      {
        section_id: sectionId,
        row_id: step.rowId,
        exercise_name: step.name,
        exercise_ref: step.exerciseRef,
        block_index: step.block,
        round_index: step.round,
        part_index: step.part?.index ?? 0,
        phase_index: phase,
        interrupt: step.interrupt,
        prescribed_reps_text: step.values.dose,
        prescribed_load_text: step.values.load,
        prescribed_reps: prescribedReps,
        prescribed_load_kg: prescribedKg,
        actual_reps: loggedReps ?? prescribedReps,
        actual_load_kg: loggedKg ?? prescribedKg,
        logged: loggedReps != null || loggedKg != null,
      },
    ];
  });
}
