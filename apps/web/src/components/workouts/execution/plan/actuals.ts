/**
 * ADR-270: what the athlete did in a plan section, one record per set /
 * round of each exercise, prescribed next to actual, for planned-vs-done
 * progress and analytics. Keyed by the plan row id and its place in the run
 * (block, round, inner part, AMRAP window), so it joins back to the plan
 * (`sections[].plan`) without depending on materialised exercise rows.
 *
 * Sent with the execution's completion as `plan_actuals`; a set the
 * athlete did not log counts as done as prescribed (`logged: false`). A load
 * prescribed in % becomes kg when the athlete's 1RM is known (their PRs).
 */
import type { PlanSetActual } from "@/api/executions";

import { logKeyOf, type RunState } from "./runner";
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
const pctOf = (load: string): number | null => {
  const m = /^(\d+(?:\.\d+)?)%$/.exec(load.trim());
  return m ? Number(m[1]) : null;
};
const round2 = (n: number) => Math.round(n * 100) / 100;

/** The athlete's 1RM in kg for an exercise, when known. */
export type OneRepMaxLookup = (name: string, exerciseRef: string | null) => number | null;

export type ActualsOptions = { oneRepMaxKg?: OneRepMaxLookup };

/** A drop set's reduction per drop: "-20%" / "20%" (of the previous drop's load) or "-10kg" / "10" (kg off each drop). */
export function dropBy(by: string): { unit: "pct" | "kg"; amount: number } | null {
  const m = /^\s*-?\s*(\d+(?:[.,]\d+)?)\s*(%|kg)?\s*$/i.exec(by);
  return m ? { unit: m[2] === "%" ? "pct" : "kg", amount: Number(m[1].replace(",", ".")) } : null;
}

/**
 * The load a step prescribes in kg: written in kg, or a % of a known 1RM.
 * A drop set's later parts are lowered by its `dropby` once per drop, as the
 * API's PlanWorkload counts them: a % compounds (100 kg, -20% → 80, 64), kg
 * come off each drop (100 kg, -10kg → 90, 80), never below zero; a % load
 * lowered by kg stays a % only when the 1RM is known.
 */
export function prescribedKg(step: RunWork, oneRepMaxKg?: OneRepMaxLookup): { kg: number | null; pct: number | null; oneRm: number | null } {
  const basePct = pctOf(step.values.load);
  const oneRm = basePct != null ? (oneRepMaxKg?.(step.name, step.exerciseRef) ?? null) : null;
  const baseKg = kgOf(step.values.load) ?? (basePct != null && oneRm != null ? round2((basePct / 100) * oneRm) : null);
  const drops = step.part?.kind === "drop" ? step.part.index : 0;
  const by = step.part?.kind === "drop" && drops > 0 ? dropBy(step.part.by) : null;
  if (!by) return { kg: baseKg, pct: basePct, oneRm };
  if (by.unit === "pct") {
    const factor = Math.max(0, 1 - by.amount / 100) ** drops;
    return {
      kg: baseKg != null ? round2(baseKg * factor) : null,
      pct: basePct != null ? round2(basePct * factor) : null,
      oneRm,
    };
  }
  const kg = baseKg != null ? round2(Math.max(0, baseKg - by.amount * drops)) : null;
  return { kg, pct: basePct != null && kg != null && oneRm ? round2((kg / oneRm) * 100) : null, oneRm };
}

function record(
  sectionId: string,
  step: RunWork,
  phase: number,
  round: number,
  log: { reps?: string; load?: string },
  options: ActualsOptions,
): PlanSetActual {
  const prescribedReps = repsOf(step.values.dose);
  const { kg, pct, oneRm } = prescribedKg(step, options.oneRepMaxKg);
  const loggedReps = decimal(log.reps);
  const loggedKg = decimal(log.load);
  return {
    section_id: sectionId,
    row_id: step.rowId,
    exercise_name: step.name,
    exercise_ref: step.exerciseRef,
    block_index: step.block,
    round_index: round,
    part_index: step.part?.index ?? 0,
    phase_index: phase,
    interrupt: step.interrupt,
    prescribed_reps_text: step.values.dose,
    prescribed_load_text: step.values.load,
    prescribed_reps: prescribedReps,
    prescribed_load_kg: kg,
    prescribed_load_pct: pct,
    one_rep_max_kg: oneRm,
    actual_reps: loggedReps ?? prescribedReps,
    actual_load_kg: loggedKg ?? kg,
    logged: loggedReps != null || loggedKg != null,
  };
}

/**
 * One record per done work step: the main run in the order done, then the
 * rows done at each interruption (`round_index` = which interruption).
 */
export function planActuals(
  seq: RunSequence,
  state: RunState,
  logs: RunLogs,
  sectionId: string,
  options: ActualsOptions = {},
): PlanSetActual[] {
  const where = new Map<string, { step: RunWork; phase: number }>();
  seq.phases.forEach((phase, p) => {
    for (const step of phase.steps) if (step.kind === "work") where.set(step.key, { step, phase: p });
  });
  const main = state.completed.flatMap((key) => {
    const found = where.get(key);
    return found ? [record(sectionId, found.step, found.phase, found.step.round, logs[key] ?? {}, options)] : [];
  });
  const rows = new Map((seq.interrupt?.steps ?? []).flatMap((s) => (s.kind === "work" ? [[s.key, s] as const] : [])));
  const interrupts = state.completedInterrupts.flatMap(({ key, fire, phase }) => {
    const step = rows.get(key);
    return step ? [record(sectionId, step, phase, fire, logs[logKeyOf(step, fire)] ?? {}, options)] : [];
  });
  return [...main, ...interrupts];
}
