import { describe, expect, it } from "vitest";
import { newRow, newSection } from "./factory";
import {
  blockLabel,
  canPerRound,
  occurrences,
  paramCount,
  paramSecs,
  roundWord,
  roundWordKey,
  setsRange,
  structOf,
  totalRounds,
  unitKey,
  unitsOf,
  usesCells,
} from "./rounds";
import type { PlanFlow, PlanParams, PlanRow, PlanSection } from "./types";

const section = (flow: PlanFlow, params: PlanParams, blocks: PlanRow[][] = [[newRow()]]): PlanSection => ({
  ...newSection(flow),
  params,
  blocks,
});

describe("units and structures", () => {
  it("groups consecutive rows of the same group into one unit", () => {
    const a = newRow("ex", { name: "Knee Extension", group: "g1" });
    const b = newRow("ex", { name: "Calf Raise", group: "g1" });
    const c = newRow("ex", { name: "Cyclist Squat" });
    const d = newRow("ex", { name: "Dip", group: "g1" });
    const units = unitsOf([a, b, c, d]);
    expect(units.map((u) => u.rows.length)).toEqual([2, 1, 1]);
    expect(unitKey(units[0])).toBe("g1");
    expect(unitKey(units[1])).toBe(c.id);
  });

  it("defaults a group to superset and one row to single, ignoring a structure that does not fit", () => {
    const a = newRow("ex", { group: "g" });
    const b = newRow("ex", { group: "g" });
    const s = section("sets", { sets: "4" }, [[a, b]]);
    const [u] = unitsOf(s.blocks[0]);
    expect(structOf(s, u)).toEqual({ kind: "superset" });
    expect(structOf({ structs: { g: { kind: "complex" } } }, u)).toEqual({ kind: "complex" });
    expect(structOf({ structs: { g: { kind: "cluster", clusters: "3", intra: "15″" } } }, u)).toEqual({ kind: "superset" });
    const [one] = unitsOf([a].map((r) => ({ ...r, group: null })));
    expect(structOf({ structs: { [a.id]: { kind: "drop", drops: "2", dropby: "-20%" } } }, one).kind).toBe("drop");
  });
});

describe("parameters", () => {
  it("reads times and counts", () => {
    expect(paramSecs({ params: { every: "2:30" } }, "every")).toBe(150);
    expect(paramSecs({ params: { cap: "20" } }, "cap")).toBe(1200);
    expect(paramSecs({ params: { rest: "90" } }, "rest")).toBe(90);
    expect(paramSecs({ params: { rest: "x" } }, "rest")).toBeNull();
    expect(paramCount({ params: { times: "4" } }, "times")).toBe(4);
    expect(paramCount({ params: { times: "" } }, "times")).toBeNull();
    expect(setsRange({ params: { sets: "3-4" } })).toEqual({ min: 3, max: 4 });
    expect(setsRange({ params: { sets: "" } })).toEqual({ min: 1, max: 1 });
  });
});

describe("totalRounds and occurrences", () => {
  it("counts sets (3-4 sets → 4 columns), EMOM times, rounds; AMRAP is open", () => {
    expect(totalRounds(section("sets", { sets: "3-4" }))).toBe(4);
    expect(totalRounds(section("emom", { every: "2:30", times: "4" }))).toBe(4);
    expect(totalRounds(section("for_time", { rounds: "4" }))).toBe(4);
    expect(totalRounds(section("for_time", { rounds: "" }))).toBe(1);
    expect(totalRounds(section("amrap", { dur: "12" }))).toBe(Infinity);
  });

  it("alternates blocks: 1, 3, 5 … / 2, 4, 6 …", () => {
    const s = section("emom", { every: "1:00", times: "8" }, [[newRow()], [newRow()]]);
    expect(occurrences(s, 0)).toEqual({ list: [1, 3, 5, 7], open: false });
    expect(occurrences(s, 1)).toEqual({ list: [2, 4, 6, 8], open: false });
  });

  it("caps columns at 12", () => {
    expect(occurrences(section("emom", { every: "1:00", times: "30" }), 0).list).toHaveLength(12);
  });

  it("shows for AMRAP the written rounds plus one empty column, at least 2, at most 12 (no fixed 4)", () => {
    const r = newRow("ex", { perRound: true, cells: [] });
    const s = section("amrap", { dur: "7" }, [[newRow(), r]]);
    expect(occurrences(s, 0)).toEqual({ list: [1, 2], open: true });
    r.cells = [{ d: "5", l: "40kg" }, { d: "10", l: "+5kg" }, { d: "15" }];
    expect(occurrences(s, 0).list).toEqual([1, 2, 3, 4]);
    r.cells = Array.from({ length: 20 }, () => ({ d: "5" }));
    expect(occurrences(s, 0).list).toHaveLength(12);
  });

  it("ignores stale cells of rows that are not per round", () => {
    const r = newRow("ex", { perRound: false, cells: [{ d: "1" }, { d: "2" }, { d: "3" }] });
    expect(occurrences(section("amrap", { dur: "7" }, [[r]]), 0).list).toEqual([1, 2]);
  });
});

describe("round words and block labels", () => {
  it("names columns per flow", () => {
    expect(roundWord({ flow: "sets" })).toBe("set");
    expect(roundWord({ flow: "emom" })).toBe("interval");
    expect(roundWord({ flow: "intervals" })).toBe("interval");
    expect(roundWord({ flow: "amrap" })).toBe("round");
    expect(roundWordKey({ flow: "for_time" })).toBe("PlanCore.roundWord.round");
  });

  it("labels EMOM minutes, slots at other spacings, single rounds and lists", () => {
    const minutes = section("emom", { every: "1:00", times: "8" }, [[newRow()], [newRow()]]);
    expect(blockLabel(minutes, 0)).toEqual({ key: "PlanCore.block.minute", values: { list: "1, 3, 5, …" } });
    const slots = section("emom", { every: "2:30", times: "4" }, [[newRow()], [newRow()]]);
    expect(blockLabel(slots, 1)).toEqual({ key: "PlanCore.block.slot", values: { word: "interval", list: "2, 4, …", at: "2:30, 7:30, …" } });
    const own = section("for_time", { rounds: "2" }, [[newRow()], [newRow()]]);
    expect(blockLabel(own, 1)).toEqual({ key: "PlanCore.block.one", values: { word: "round", n: 2 } });
    const alt = section("for_time", { rounds: "4" }, [[newRow()], [newRow()]]);
    expect(blockLabel(alt, 0)).toEqual({ key: "PlanCore.block.list", values: { word: "round", list: "1, 3" } });
    const amrap = section("amrap", { dur: "12" }, [[newRow()], [newRow()]]);
    expect(blockLabel(amrap, 0)).toEqual({ key: "PlanCore.block.list", values: { word: "round", list: "1, 3, …" } });
  });

  it("allows values per round only outside the sets grid and when the block runs more than once", () => {
    expect(canPerRound(section("sets", { sets: "4" }), 0)).toBe(false);
    expect(canPerRound(section("for_time", { rounds: "1" }), 0)).toBe(false);
    expect(canPerRound(section("for_time", { rounds: "3" }), 0)).toBe(true);
    expect(canPerRound(section("amrap", { dur: "7" }), 0)).toBe(true);
    expect(canPerRound(section("emom", { every: "1:00", times: "10" }), -1)).toBe(false);
    expect(usesCells({ flow: "sets" }, {})).toBe(true);
    expect(usesCells({ flow: "amrap" }, { perRound: true })).toBe(true);
    expect(usesCells({ flow: "amrap" }, {})).toBe(false);
  });
});
