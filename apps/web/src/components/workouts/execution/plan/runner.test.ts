import { describe, expect, it } from "vitest";

import type { PlanRow, PlanSection } from "@/lib/structured-plan/types";

import { currentStep, initialRunState, phaseRemainingMs, type RunAction, runReducer, type RunState, upcomingStep } from "./runner";
import { measuredScore, roundsAndReps } from "./score";
import { buildSequence, type RunSequence } from "./sequence";

let uid = 0;
const ex = (name: string, dose: string, more: Partial<PlanRow> = {}): PlanRow => ({ id: `r${uid++}`, kind: "ex", name, dose, load: "", cells: [], ...more });
const section = (flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  v: 1,
  flow,
  params,
  blocks,
  score: "",
  ...more,
});

function run(seq: RunSequence, ...actions: RunAction[]): RunState {
  return actions.reduce((s, a) => runReducer(seq, s, a), initialRunState());
}
const at = (secs: number): RunAction => ({ type: "tick", elapsedMs: secs * 1000 });
const NEXT: RunAction = { type: "next" };
const name = (seq: RunSequence, s: RunState) => {
  const step = currentStep(seq, s);
  return step?.kind === "work" ? step.name : step?.kind ?? null;
};

describe("runReducer", () => {
  it("waits for start, then steps through and finishes For Time with its time", () => {
    const seq = buildSequence(section("for_time", { rounds: "2" }, [[ex("Row", "250 m"), ex("Burpee", "10")]]));
    let s = run(seq, NEXT);
    expect(s.status).toBe("ready");
    s = run(seq, { type: "start" }, at(30), NEXT, at(50), NEXT, NEXT);
    expect(name(seq, s)).toBe("Burpee");
    expect(upcomingStep(seq, s)).toBeNull();
    s = runReducer(seq, runReducer(seq, s, at(95)), NEXT);
    expect(s.status).toBe("done");
    expect(s.finishedAtMs).toBe(95_000);
    expect(measuredScore(seq, s, "time")).toBe("1:35");
  });

  it("ends For Time at the cap and scores rounds + reps", () => {
    const seq = buildSequence(section("for_time", { rounds: "3", cap: "10" }, [[ex("Thruster", "15"), ex("Pull-up", "12")]]));
    const s = run(seq, { type: "start" }, NEXT, NEXT, NEXT, at(600));
    expect(s.status).toBe("done");
    expect(s.timeUp).toBe(true);
    expect(measuredScore(seq, s, "time")).toBeNull();
    expect(measuredScore(seq, s, "rounds_reps")).toBe("1+15");
  });

  it("interrupts every 2 minutes and resumes the main work where it was", () => {
    const seq = buildSequence(
      section("for_time", { rounds: "1", intEvery: "2:00" }, [[ex("Thruster", "75")]], { mods: { interrupt: true }, interrupt: [ex("Burpee over Bar", "10")] }),
    );
    let s = run(seq, { type: "start" }, at(119));
    expect(name(seq, s)).toBe("Thruster");
    s = runReducer(seq, s, at(120));
    expect(name(seq, s)).toBe("Burpee over Bar");
    expect(upcomingStep(seq, s)).toMatchObject({ name: "Thruster" });
    s = runReducer(seq, runReducer(seq, s, at(150)), NEXT);
    expect(name(seq, s)).toBe("Thruster");
    expect(s.interrupt).toBeNull();
    s = runReducer(seq, s, at(239));
    expect(s.interrupt).toBeNull();
    s = runReducer(seq, s, at(240));
    expect(s.interruptsFired).toBe(2);
    expect(name(seq, s)).toBe("Burpee over Bar");
  });

  it("moves EMOM slots on the clock and waits when the athlete is done early", () => {
    const seq = buildSequence(section("emom", { every: "1:00", times: "3" }, [[ex("Wall Ball", "20")], [ex("Burpee", "12")]]));
    let s = run(seq, { type: "start" }, at(20), NEXT);
    expect(currentStep(seq, s)).toBeNull();
    expect(phaseRemainingMs(seq, s)).toBe(40_000);
    s = runReducer(seq, s, NEXT);
    expect(s.phase).toBe(0);
    s = runReducer(seq, s, at(60));
    expect(name(seq, s)).toBe("Burpee");
    s = runReducer(seq, s, at(185));
    expect(s.status).toBe("done");
  });

  it("runs AMRAP windows and their rest on the clock and counts rounds + reps across windows", () => {
    const seq = buildSequence(section("amrap", { dur: "3-3", rest: "1:00" }, [[ex("Echo Bike", "15 cal"), ex("Wall Ball", "25")]]));
    let s = run(seq, { type: "start" }, NEXT, NEXT, NEXT, at(180));
    expect(seq.phases[s.phase].kind).toBe("rest");
    expect(runReducer(seq, s, NEXT)).toBe(s);
    s = runReducer(seq, s, at(240));
    expect(s.phase).toBe(2);
    s = [NEXT, NEXT, NEXT].reduce((x, a) => runReducer(seq, x, a), s);
    expect(roundsAndReps(seq, s)).toEqual({ rounds: 2, reps: 15 + 15 });
    s = runReducer(seq, s, at(420));
    expect(s.status).toBe("done");
  });

  it("runs timed rests out on their own in sets; a rest range waits for the athlete", () => {
    const seq = buildSequence(section("sets", { sets: "2", rest: "90″" }, [[ex("Squat", "", { cells: [{ d: "5", l: "100kg" }] })]]));
    let s = run(seq, { type: "start" }, at(40), NEXT);
    expect(currentStep(seq, s)?.kind).toBe("rest");
    s = runReducer(seq, s, at(130));
    expect(name(seq, s)).toBe("Squat");
    expect(s.stepStartMs).toBe(130_000);

    const ranged = buildSequence(section("sets", { sets: "2", rest: "90-120″" }, [[ex("Squat", "", { cells: [{ d: "5", l: "100kg" }] })]]));
    const r = run(ranged, { type: "start" }, NEXT, at(500));
    expect(currentStep(ranged, r)?.kind).toBe("rest");
  });

  it("ends a heart-rate rest on the athlete's tap", () => {
    const seq = buildSequence(section("intervals", { work: "3:00", rounds: "2", hrTarget: "120" }, [[ex("Row", "max m")]], { mods: { hr: true } }));
    let s = run(seq, { type: "start" }, at(180));
    expect(currentStep(seq, s)).toMatchObject({ kind: "rest", untilHr: 120 });
    s = runReducer(seq, s, at(260));
    expect(s.phase).toBe(1);
    s = runReducer(seq, s, NEXT);
    expect(s.phase).toBe(2);
    expect(s.phaseStartMs).toBe(260_000);
    expect(phaseRemainingMs(seq, s)).toBe(180_000);
  });

  it("goes back one step and forgets it was done; pause freezes the clock", () => {
    const seq = buildSequence(section("for_time", {}, [[ex("A", "1"), ex("B", "2")]]));
    let s = run(seq, { type: "start" }, NEXT);
    expect(s.completed).toHaveLength(1);
    s = runReducer(seq, s, { type: "prev" });
    expect(name(seq, s)).toBe("A");
    expect(s.completed).toHaveLength(0);
    s = runReducer(seq, runReducer(seq, s, { type: "pause" }), at(10));
    expect(s.elapsedMs).toBe(0);
  });
});
