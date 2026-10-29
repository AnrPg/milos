import { describe, expect, it } from "vitest";

import type { PlanRow, PlanSection } from "@/lib/structured-plan/types";

import { decimal, dropBy, planActuals } from "./actuals";
import { initialRunState, logKeyOf, type RunAction, runReducer } from "./runner";
import { buildSequence } from "./sequence";

const row = (id: string, name: string, more: Partial<PlanRow> = {}): PlanRow => ({ id, kind: "ex", name, dose: "", load: "", cells: [], ...more });
const NEXT: RunAction = { type: "next" };

describe("decimal", () => {
  it("reads decimal kg with a dot or a comma", () => {
    expect(decimal("22.5")).toBe(22.5);
    expect(decimal("22,5")).toBe(22.5);
    expect(decimal("65 kg")).toBe(65);
    expect(decimal("βαρύ")).toBeNull();
  });
});

describe("planActuals", () => {
  it("records prescribed vs actual per set, keyed by row, block, round and part", () => {
    const section: PlanSection = {
      v: 1,
      flow: "sets",
      params: { sets: "2" },
      blocks: [[
        row("bench", "Bench Press", { group: "g", cells: [{ d: "12", l: "60kg" }, { d: "10", l: "+2.5" }] }),
        row("fly", "DB Fly", { group: "g", cells: [{ d: "15", l: "70%" }] }),
      ]],
      score: "none",
    };
    const seq = buildSequence(section);
    const state = [{ type: "start" } as RunAction, NEXT, NEXT, NEXT].reduce((s, a) => runReducer(seq, s, a), initialRunState());
    const steps = seq.phases[0].steps;
    const logs = { [steps[2].key]: { reps: "9", load: "62,5" } };
    expect(planActuals(seq, state, logs, "sec-1")).toEqual([
      expect.objectContaining({ row_id: "bench", block_index: 0, round_index: 1, part_index: 0, phase_index: 0, prescribed_reps: 12, prescribed_load_kg: 60, actual_reps: 12, actual_load_kg: 60, logged: false }),
      expect.objectContaining({ row_id: "fly", round_index: 1, prescribed_load_text: "70%", prescribed_load_kg: null, actual_load_kg: null, logged: false }),
      expect.objectContaining({ section_id: "sec-1", row_id: "bench", round_index: 2, prescribed_reps: 10, prescribed_load_kg: 62.5, actual_reps: 9, actual_load_kg: 62.5, logged: true }),
    ]);
  });

  it("tells AMRAP windows and alternating blocks apart", () => {
    const section: PlanSection = {
      v: 1,
      flow: "amrap",
      params: { dur: "1-1" },
      blocks: [[row("a", "Wall Ball", { dose: "20" })], [row("b", "Burpee", { dose: "10" })]],
      score: "rounds_reps",
    };
    const seq = buildSequence(section);
    let s = [{ type: "start" } as RunAction, NEXT, NEXT, { type: "tick", elapsedMs: 60_000 } as RunAction, NEXT].reduce((x, a) => runReducer(seq, x, a), initialRunState());
    s = runReducer(seq, s, { type: "tick", elapsedMs: 120_000 });
    expect(planActuals(seq, s, {}, "s").map((a) => [a.row_id, a.block_index, a.round_index, a.phase_index])).toEqual([
      ["a", 0, 1, 0],
      ["b", 1, 2, 0],
      ["a", 0, 1, 1],
    ]);
  });

  it("includes the rows done at every interruption, each with its own log", () => {
    const section: PlanSection = {
      v: 1,
      flow: "for_time",
      params: { rounds: "1", intEvery: "2:00" },
      mods: { interrupt: true },
      blocks: [[row("thr", "Thruster", { dose: "75" })]],
      interrupt: [row("bur", "Burpee over Bar", { dose: "10" })],
      score: "time",
    };
    const seq = buildSequence(section);
    const tick = (s: number): RunAction => ({ type: "tick", elapsedMs: s * 1000 });
    const state = [{ type: "start" } as RunAction, tick(120), NEXT, tick(240), NEXT, tick(300), NEXT].reduce((s, a) => runReducer(seq, s, a), initialRunState());
    expect(state.status).toBe("done");
    const burpee = seq.interrupt!.steps[0];
    const logs = { [logKeyOf(burpee, 2)]: { reps: "8" } };
    expect(planActuals(seq, state, logs, "s").map((a) => [a.row_id, a.interrupt, a.block_index, a.round_index, a.actual_reps, a.logged])).toEqual([
      ["thr", false, 0, 1, 75, false],
      ["bur", true, -1, 1, 10, false],
      ["bur", true, -1, 2, 8, true],
    ]);
  });

  it("turns a % load into kg with the athlete's 1RM, else keeps kg null", () => {
    const section: PlanSection = {
      v: 1,
      flow: "sets",
      params: { sets: "1" },
      blocks: [[row("sq", "Back Squat", { cells: [{ d: "5", l: "70%" }] })]],
      score: "none",
    };
    const seq = buildSequence(section);
    const state = [{ type: "start" } as RunAction, NEXT].reduce((s, a) => runReducer(seq, s, a), initialRunState());
    const [known] = planActuals(seq, state, {}, "s", { oneRepMaxKg: (name) => (name === "Back Squat" ? 142.5 : null) });
    expect(known).toMatchObject({ prescribed_load_pct: 70, one_rep_max_kg: 142.5, prescribed_load_kg: 99.75, actual_load_kg: 99.75 });
    const [unknown] = planActuals(seq, state, {}, "s");
    expect(unknown).toMatchObject({ prescribed_load_pct: 70, one_rep_max_kg: null, prescribed_load_kg: null, actual_load_kg: null });
  });

  describe("drop sets", () => {
    const dropSection = (load: string, dropby: string): PlanSection => ({
      v: 1,
      flow: "sets",
      params: { sets: "1" },
      blocks: [[row("sq", "Back Squat", { cells: [{ d: "8", l: load }] })]],
      structs: { sq: { kind: "drop", drops: "2", dropby } },
      score: "none",
    });
    const run = (section: PlanSection, logs: Record<number, { reps?: string; load?: string }> = {}, options = {}) => {
      const seq = buildSequence(section);
      const steps = seq.phases[0].steps.filter((s) => s.kind === "work");
      const state = [{ type: "start" } as RunAction, NEXT, NEXT, NEXT].reduce((s, a) => runReducer(seq, s, a), initialRunState());
      const keyed = Object.fromEntries(Object.entries(logs).map(([i, log]) => [steps[Number(i)].key, log]));
      return planActuals(seq, state, keyed, "s", options);
    };

    it("lowers a kg load by a % per drop, compounding", () => {
      expect(run(dropSection("100kg", "-20%")).map((a) => [a.part_index, a.prescribed_reps, a.prescribed_load_kg, a.actual_load_kg])).toEqual([
        [0, 8, 100, 100],
        [1, 8, 80, 80],
        [2, 8, 64, 64],
      ]);
    });

    it("takes kg off each drop, never below zero", () => {
      expect(run(dropSection("100kg", "-10kg")).map((a) => a.prescribed_load_kg)).toEqual([100, 90, 80]);
      expect(run(dropSection("15kg", "10")).map((a) => a.prescribed_load_kg)).toEqual([15, 5, 0]);
    });

    it("lowers a % of 1RM load too, kg only when the 1RM is known", () => {
      const oneRepMaxKg = () => 150;
      expect(run(dropSection("80%", "-25%"), {}, { oneRepMaxKg }).map((a) => [a.prescribed_load_pct, a.prescribed_load_kg])).toEqual([
        [80, 120],
        [60, 90],
        [45, 67.5],
      ]);
      expect(run(dropSection("80%", "-25%")).map((a) => [a.prescribed_load_pct, a.prescribed_load_kg])).toEqual([
        [80, null],
        [60, null],
        [45, null],
      ]);
      expect(run(dropSection("80%", "-15kg"), {}, { oneRepMaxKg }).map((a) => [a.prescribed_load_pct, a.prescribed_load_kg])).toEqual([
        [80, 120],
        [70, 105],
        [60, 90],
      ]);
    });

    it("keeps what the athlete logged and the base load when dropby is not a number", () => {
      expect(run(dropSection("100kg", "-20%"), { 2: { load: "60" } }).map((a) => a.actual_load_kg)).toEqual([100, 80, 60]);
      expect(run(dropSection("100kg", "lighter")).map((a) => a.prescribed_load_kg)).toEqual([100, 100, 100]);
    });

    it("reads dropby as % or kg", () => {
      expect(dropBy("-20%")).toEqual({ unit: "pct", amount: 20 });
      expect(dropBy(" 2,5 kg ")).toEqual({ unit: "kg", amount: 2.5 });
      expect(dropBy("10")).toEqual({ unit: "kg", amount: 10 });
      expect(dropBy("")).toBeNull();
    });
  });
});
