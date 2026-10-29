/**
 * ADR-270: the score of a plan section at the end of its run. The score keys
 * come from the catalog (`FLOWS[flow].scores`); this maps them onto the
 * existing score model (`ScoreModal`, `FinishWizard`, `SectionScore`) and
 * measures what the run can tell: time for For Time, rounds + reps for
 * AMRAP, total reps, best load, lowest round, distance. The athlete always
 * confirms or corrects it.
 */
import type { TimerSegment } from "@/api/executions";
import type { ScoreKey } from "@/lib/structured-plan/catalog";

import { formatClock } from "../TimerDisplay";
import type { RunState } from "./runner";
import type { RunSequence, RunWork } from "./sequence";

/** What the athlete logged on one step: actual reps and load, as typed. */
export type StepLog = { reps?: string; load?: string };
export type RunLogs = Record<string, StepLog>;

/** `ScoreModal` / `FinishWizard` score types per catalog key; null = not scored. */
const SCORE_TYPES: Record<ScoreKey, { type: string; unit?: string } | null> = {
  none: null,
  time: { type: "time" },
  rounds_reps: { type: "rounds_reps" },
  reps: { type: "reps" },
  total_reps: { type: "reps" },
  lowest_round: { type: "reps" },
  best_load: { type: "load", unit: "kg" },
  done: { type: "pass_fail" },
  distance: { type: "reps", unit: "m" },
};

export function scoreConfig(key: string | null | undefined): { type: string; unit?: string } | null {
  if (!key || !(key in SCORE_TYPES)) return null;
  return SCORE_TYPES[key as ScoreKey];
}

/** A `TimerSegment` that carries a plan section's score into `ScoreModal` and `FinishWizard`. */
export function scoreSegment(sectionId: string, sectionName: string, scoreKey: string, label: string): TimerSegment | null {
  const config = scoreConfig(scoreKey);
  if (!config) return null;
  return {
    segment_key: `plan:${sectionId}`,
    section_id: sectionId,
    section_name: sectionName,
    format: "structured_plan",
    kind: "manual",
    duration_seconds: null,
    round: null,
    total_rounds: null,
    label: sectionName,
    scoreable: true,
    score_config: { ...config, label },
    exercises: [],
  };
}

const plainNumber = (text: string | undefined): number | null => {
  const m = /^\s*(\d+(?:[.,]\d+)?)\s*$/.exec(text ?? "");
  return m ? Number(m[1].replace(",", ".")) : null;
};

/** Reps of a done step: what the athlete logged, else the target when it is a number of reps or calories. */
const repsOf = (step: RunWork, logs: RunLogs) =>
  plainNumber(logs[step.key]?.reps) ?? plainNumber(step.values.dose.replace(/\s*cal$/, ""));

/** Load in kg of a done step: logged, else the target when written in kg. */
function kgOf(step: RunWork, logs: RunLogs): number | null {
  const logged = plainNumber(logs[step.key]?.load);
  if (logged != null) return logged;
  const m = /^(\d+(?:\.\d+)?) kg$/.exec(step.values.load.trim());
  return m ? Number(m[1]) : null;
}

const metresOf = (step: RunWork): number | null => {
  const m = /^(\d+(?:\.\d+)?) (m|km)$/.exec(step.values.dose.trim());
  return m ? Number(m[1]) * (m[2] === "km" ? 1000 : 1) : null;
};

/** Done work steps, with the index of their phase. */
function doneWork(seq: RunSequence, state: RunState): { phase: number; step: RunWork }[] {
  const done = new Set(state.completed);
  return seq.phases.flatMap((phase, p) =>
    phase.steps.filter((s): s is RunWork => s.kind === "work" && done.has(s.key)).map((step) => ({ phase: p, step })),
  );
}

/** Full rounds and the reps of the round in progress, over every window. */
export function roundsAndReps(seq: RunSequence, state: RunState, logs: RunLogs = {}): { rounds: number; reps: number } {
  const done = new Set(state.completed);
  let rounds = 0;
  let reps = 0;
  for (const phase of seq.phases) {
    const byRound = new Map<number, RunWork[]>();
    for (const s of phase.steps) if (s.kind === "work") byRound.set(s.round, [...(byRound.get(s.round) ?? []), s]);
    for (const steps of byRound.values()) {
      if (steps.every((s) => done.has(s.key))) rounds += 1;
      else for (const s of steps) if (done.has(s.key)) reps += repsOf(s, logs) ?? 0;
    }
  }
  return { rounds, reps };
}

/** The measured score to pre-fill, or null when the run cannot tell. */
export function measuredScore(seq: RunSequence, state: RunState, scoreKey: string, logs: RunLogs = {}): string | null {
  const done = doneWork(seq, state);
  switch (scoreKey) {
    case "time":
      if (state.finishedAtMs != null && !state.timeUp) return formatClock(Math.round(state.finishedAtMs / 1000));
      return null;
    case "rounds_reps": {
      const { rounds, reps } = roundsAndReps(seq, state, logs);
      return done.length ? `${rounds}+${reps}` : null;
    }
    case "reps":
    case "total_reps": {
      const total = done.reduce((sum, d) => sum + (repsOf(d.step, logs) ?? 0), 0);
      return total > 0 ? String(total) : null;
    }
    case "best_load": {
      const loads = done.map((d) => kgOf(d.step, logs)).filter((n): n is number => n != null);
      return loads.length ? String(Math.max(...loads)) : null;
    }
    case "lowest_round": {
      const perRound = new Map<string, number>();
      for (const d of done) {
        const k = `${d.phase}:${d.step.round}`;
        perRound.set(k, (perRound.get(k) ?? 0) + (repsOf(d.step, logs) ?? 0));
      }
      return perRound.size ? String(Math.min(...perRound.values())) : null;
    }
    case "distance": {
      const total = done.reduce((sum, d) => sum + (metresOf(d.step) ?? 0), 0);
      return total > 0 ? String(total) : null;
    }
    default:
      return null;
  }
}
