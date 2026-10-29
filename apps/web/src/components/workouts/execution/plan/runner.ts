/**
 * ADR-270: the state of running one plan section, as a pure reducer over its
 * run sequence. The screen feeds it the clock (`tick`, in ms of running
 * time) and the athlete's taps (`next`, `prev`); the clock moves timed
 * phases on (EMOM slots, intervals, AMRAP windows), ends For Time at its cap,
 * runs timed rests out and fires interruptions, which pause the main work
 * and resume it where it was.
 */
import type { RunPhase, RunSequence, RunStep } from "./sequence";

export type RunStatus = "ready" | "running" | "paused" | "done";

export type RunState = {
  status: RunStatus;
  /** Running time of the section's clock (pauses excluded). */
  elapsedMs: number;
  phase: number;
  /** Index in the phase's steps; `steps.length` = done early, waiting for the clock. */
  step: number;
  phaseStartMs: number;
  stepStartMs: number;
  /** The interruption being done, if any. */
  interrupt: { step: number; stepStartMs: number } | null;
  interruptsFired: number;
  /** Keys of the main-work steps done, in order. */
  completed: string[];
  /** When the athlete finished every step (For Time), in clock ms. */
  finishedAtMs: number | null;
  /** The clock ran out before the work was done (cap, last window or slot). */
  timeUp: boolean;
};

export type RunAction =
  | { type: "start" }
  | { type: "pause" }
  | { type: "resume" }
  | { type: "tick"; elapsedMs: number }
  | { type: "next" }
  | { type: "prev" }
  | { type: "finish" };

export const initialRunState = (): RunState => ({
  status: "ready",
  elapsedMs: 0,
  phase: 0,
  step: 0,
  phaseStartMs: 0,
  stepStartMs: 0,
  interrupt: null,
  interruptsFired: 0,
  completed: [],
  finishedAtMs: null,
  timeUp: false,
});

/** The step on screen: an interruption row, a main step, or null while waiting for the clock. */
export function currentStep(seq: RunSequence, state: RunState): RunStep | null {
  if (state.interrupt && seq.interrupt) return seq.interrupt.steps[state.interrupt.step] ?? null;
  return seq.phases[state.phase]?.steps[state.step] ?? null;
}

/** The step after the current one, looking into the next phase. */
export function upcomingStep(seq: RunSequence, state: RunState): RunStep | null {
  if (state.interrupt && seq.interrupt) {
    return seq.interrupt.steps[state.interrupt.step + 1] ?? seq.phases[state.phase]?.steps[state.step] ?? null;
  }
  const here = seq.phases[state.phase]?.steps[state.step + 1];
  if (here) return here;
  for (let p = state.phase + 1; p < seq.phases.length; p++) {
    const first = seq.phases[p].steps.find((s) => s.kind === "work") ?? seq.phases[p].steps[0];
    if (first) return first;
  }
  return null;
}

/** A phase ends when its steps are done (untimed phases, and For Time whose only limit is the cap). */
const endsOnCompletion = (seq: RunSequence, phase: RunPhase) => phase.secs == null || seq.flow === "for_time";

/** Seconds left in the current phase, or null when it has no length. */
export function phaseRemainingMs(seq: RunSequence, state: RunState): number | null {
  const phase = seq.phases[state.phase];
  if (!phase || phase.secs == null) return null;
  return Math.max(0, phase.secs * 1000 - (state.elapsedMs - state.phaseStartMs));
}

function done(state: RunState, extra: Partial<RunState> = {}): RunState {
  return { ...state, status: "done", interrupt: null, ...extra };
}

function toPhase(seq: RunSequence, state: RunState, phase: number, startMs: number): RunState {
  if (phase >= seq.phases.length) return done(state, { timeUp: state.finishedAtMs == null && seq.flow !== "sets" });
  return { ...state, phase, step: 0, phaseStartMs: startMs, stepStartMs: startMs, interrupt: null };
}

function advanceMain(seq: RunSequence, state: RunState, at = state.elapsedMs): RunState {
  const phase = seq.phases[state.phase];
  if (!phase) return done(state);
  const step = phase.steps[state.step];
  const completed = step && step.kind === "work" ? [...state.completed, step.key] : state.completed;
  const nextIndex = Math.min(state.step + 1, phase.steps.length);
  const moved = { ...state, completed, step: nextIndex, stepStartMs: at };
  if (nextIndex < phase.steps.length || !endsOnCompletion(seq, phase)) return moved;
  if (state.phase + 1 >= seq.phases.length) return done(moved, { finishedAtMs: at });
  return toPhase(seq, moved, state.phase + 1, at);
}

/** Moves the clock on and applies everything time decides. */
function onClock(seq: RunSequence, state: RunState): RunState {
  let s = state;
  for (let guard = 0; guard < 1000 && s.status === "running"; guard++) {
    if (seq.capSecs != null && s.elapsedMs >= seq.capSecs * 1000) return done(s, { timeUp: true });
    const phase = seq.phases[s.phase];
    if (!phase) return done(s);
    // Timed phases end on the clock, whatever is left.
    if (phase.secs != null && seq.flow !== "for_time" && s.elapsedMs - s.phaseStartMs >= phase.secs * 1000) {
      s = toPhase(seq, s, s.phase + 1, s.phaseStartMs + phase.secs * 1000);
      continue;
    }
    // Interruptions, during the main work only.
    if (seq.interrupt && !s.interrupt && phase.kind === "work" && s.step < phase.steps.length) {
      const due = Math.floor(s.elapsedMs / (seq.interrupt.everySecs * 1000));
      if (due > s.interruptsFired) {
        s = { ...s, interrupt: { step: 0, stepStartMs: s.elapsedMs }, interruptsFired: s.interruptsFired + 1 };
        continue;
      }
    }
    // A timed rest runs out on its own.
    const step = currentStep(seq, s);
    if (step?.kind === "rest" && step.secs != null && phase.kind === "work") {
      const started = s.interrupt ? s.interrupt.stepStartMs : s.stepStartMs;
      if (s.elapsedMs - started >= step.secs * 1000) {
        s = s.interrupt ? advanceInterrupt(seq, s, started + step.secs * 1000) : advanceMain(seq, s, started + step.secs * 1000);
        continue;
      }
    }
    return s;
  }
  return s;
}

function advanceInterrupt(seq: RunSequence, state: RunState, at = state.elapsedMs): RunState {
  if (!state.interrupt || !seq.interrupt) return state;
  const next = state.interrupt.step + 1;
  if (next >= seq.interrupt.steps.length) return { ...state, interrupt: null };
  return { ...state, interrupt: { step: next, stepStartMs: at } };
}

export function runReducer(seq: RunSequence, state: RunState, action: RunAction): RunState {
  switch (action.type) {
    case "start":
      return state.status === "ready" ? onClock(seq, { ...state, status: "running" }) : state;
    case "pause":
      return state.status === "running" ? { ...state, status: "paused" } : state;
    case "resume":
      return state.status === "paused" ? { ...state, status: "running" } : state;
    case "finish":
      return state.status === "done" ? state : done(state, { finishedAtMs: state.finishedAtMs ?? state.elapsedMs });
    case "tick":
      if (state.status !== "running" || action.elapsedMs < state.elapsedMs) return state;
      return onClock(seq, { ...state, elapsedMs: action.elapsedMs });
    case "next": {
      if (state.status !== "running") return state;
      if (state.interrupt) return onClock(seq, advanceInterrupt(seq, state));
      const phase = seq.phases[state.phase];
      // Waiting for the clock, or in a timed rest between slots: the clock decides.
      if (!phase || state.step >= phase.steps.length) return state;
      if (phase.kind === "rest" && phase.secs != null) return state;
      return onClock(seq, advanceMain(seq, state));
    }
    case "prev": {
      if (state.status !== "running" && state.status !== "paused") return state;
      if (state.interrupt) {
        return state.interrupt.step > 0
          ? { ...state, interrupt: { step: state.interrupt.step - 1, stepStartMs: state.elapsedMs } }
          : state;
      }
      if (state.step === 0) return state;
      const phase = seq.phases[state.phase];
      const back = phase.steps[state.step - 1];
      const completed = back?.kind === "work" ? state.completed.filter((k) => k !== back.key) : state.completed;
      return { ...state, step: state.step - 1, stepStartMs: state.elapsedMs, completed };
    }
  }
}
