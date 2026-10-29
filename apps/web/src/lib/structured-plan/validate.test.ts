import { describe, expect, it } from "vitest";
import { newRow, newSection } from "./factory";
import { PLAN_LIMITS, measureIssue, paramValid, validateSection } from "./validate";
import type { PlanFlow, PlanParams, PlanRow, PlanSection } from "./types";

const section = (flow: PlanFlow, params: PlanParams, blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  ...newSection(flow),
  params,
  blocks,
  ...more,
});
const codes = (s: PlanSection) => validateSection(s).map((i) => `${i.path}:${i.code}`);

/** The coach's reference program (mockup sample), every section of it. */
function referenceProgram(): PlanSection[] {
  const g1 = "g1";
  const g2 = "g2";
  const g3 = "g3";
  const sq = newRow("ex", { name: "Back Squat", cells: [{ d: "3", l: "80%" }] });
  return [
    section("sets", { sets: "4", rest: "2:00" }, [[newRow("ex", { name: "Back Squat", extra: ["tempo"], cells: [{ d: "12", l: "60%", tempo: "31X1" }, { d: "10", l: "+5" }, { d: "8" }, { d: "8" }] })]]),
    section("sets", { sets: "3-4", rest: "90-120″" }, [[
      newRow("ex", { name: "Knee Extension", group: g1, cells: [{ d: "12-15" }] }),
      newRow("ex", { name: "Standing Calf Raise", group: g1, cells: [{ d: "15" }] }),
      newRow("ex", { name: "Cyclist Squat", group: g1, cells: [{ d: "20" }] }),
    ]]),
    section("sets", { sets: "4", rest: "3:00" }, [[
      newRow("ex", { name: "Ring Dip", group: g2, cells: [{ d: "7", l: "με βάρος" }] }),
      newRow("rest", { group: g2, cells: [{ d: "30″" }] }),
      newRow("ex", { name: "Strict HSPU", group: g2, cells: [{ d: "10" }] }),
      newRow("rest", { group: g2, cells: [{ d: "30″" }] }),
      newRow("ex", { name: "Echo Bike", group: g2, cells: [{ d: "60s max cal" }] }),
    ]]),
    section("sets", { sets: "5", rest: "2:30" }, [[sq]], { structs: { [sq.id]: { kind: "cluster", clusters: "3", intra: "15″" } } }),
    section("emom", { every: "2:30", times: "4" }, [[
      newRow("ex", { name: "Front Squat", dose: "7", group: g3 }),
      newRow("ex", { name: "Dual DB Push Press", dose: "8-12", load: "βαρύ", group: g3 }),
    ]]),
    section("emom", { every: "1:00", times: "8" }, [[newRow("ex", { name: "Wall Ball", dose: "20" })], [newRow("ex", { name: "Burpee to Target", dose: "12" })]], { preset: "even_odd" }),
    section("amrap", { dur: "7", rest: "" }, [[
      newRow("ex", { name: "Butterfly Pull-up", dose: "15" }),
      newRow("ex", { name: "Power Snatch", perRound: true, cells: [{ d: "5", l: "40kg" }, { d: "10", l: "+5kg" }, { d: "15" }] }),
    ]]),
    section("amrap", { dur: "12" }, [[newRow("ex", { name: "Thruster", dose: "5-10-15…", load: "22.5kg" })]]),
    section("for_time", { rounds: "1", cap: "", intEvery: "2:00" }, [[newRow("ex", { name: "Thruster", dose: "75" })]], {
      mods: { interrupt: true },
      interrupt: [newRow("ex", { name: "Burpee over Bar", dose: "10" })],
      preset: "interrupt",
    }),
    section("for_time", { rounds: "4", cap: "20" }, [[newRow("ex", { name: "Row", dose: "500 m" }), newRow("ex", { name: "Burpee", dose: "15" })], [newRow("ex", { name: "Run", dose: "400 m" }), newRow("ex", { name: "Wall Ball", dose: "20" })]]),
    section("amrap", { dur: "3'-3'-3'-4'", rest: "1:00" }, [[newRow("ex", { name: "Echo Bike", dose: "15 cal" }), newRow("ex", { name: "Wall Ball", dose: "25" }), newRow("ex", { name: "Clean & Jerk", dose: "max", load: "60kg" })]], { score: "rounds_reps" }),
    section("sets", { sets: "4", rest: "90″" }, [[newRow("ex", { name: "Bulgarian Split Squat", extra: ["side", "rpe"], cells: [{ d: "4 x 8-10 each side", l: "22.5kg", rpe: "8" }] })]]),
    section("intervals", { work: "20″", off: "10″", rounds: "8" }, [[newRow("ex", { name: "Echo Bike", dose: "max cal" })]], { score: "total_reps" }),
    section("sets", { sets: "4" }, [[newRow("ex", { name: "Bench Press", cells: [{ d: "8", l: "60→80%" }] })]]),
  ];
}

describe("validateSection (ADR-270)", () => {
  it("accepts every section of the reference program", () => {
    for (const s of referenceProgram()) expect(codes(s)).toEqual([]);
  });

  it("refuses an unknown flow and a wrong version", () => {
    expect(codes({ ...newSection("sets"), flow: "yoga" as PlanFlow })).toEqual(["flow:unknown_flow"]);
    expect(codes({ ...newSection("sets"), v: 2 as 1 })).toEqual(["v:bad_version"]);
  });

  it("reads params per kind", () => {
    expect(codes(section("sets", { sets: "3-4", rest: "90-120″" }, [[newRow()]]))).toEqual([]);
    expect(codes(section("sets", { sets: "4-3", rest: "120-90″" }, [[newRow()]]))).toEqual(["params.sets:bad_param", "params.rest:bad_param"]);
    expect(codes(section("emom", { every: "soon", times: "x" }, [[newRow()]]))).toEqual(["params.every:bad_param", "params.times:bad_param"]);
    expect(codes(section("emom", { every: "1:00", times: "" }, [[newRow()]]))).toEqual([]);
    expect(codes(section("amrap", { dur: "3-0-3" }, [[newRow()]]))).toEqual(["params.dur:bad_param"]);
    expect(codes(section("for_time", { rounds: "1", work: "20″" }, [[newRow()]]))).toEqual(["params.work:unknown_param"]);
    // an add-on switched off may leave its value behind
    expect(codes(section("for_time", { rounds: "1", intEvery: "2:00" }, [[newRow()]]))).toEqual([]);
    expect(codes(section("for_time", { rounds: "1", intEvery: "x" }, [[newRow()]], { mods: { interrupt: true } }))).toEqual(["params.intEvery:bad_param"]);
  });

  it("allows add-ons and structures only where the flow allows them", () => {
    expect(codes(section("emom", { every: "1:00", times: "10" }, [[newRow()]], { mods: { interrupt: true } }))).toEqual(["mods.interrupt:mod_not_allowed"]);
    const r = newRow();
    expect(codes(section("amrap", { dur: "12" }, [[r]], { structs: { [r.id]: { kind: "drop", drops: "2", dropby: "-20%" } } }))).toEqual([`structs.${r.id}:struct_not_allowed`]);
    expect(codes(section("sets", { sets: "4" }, [[r]], { structs: { [r.id]: { kind: "cluster", clusters: "x", intra: "soon" } } }))).toEqual([
      `structs.${r.id}.clusters:bad_struct_param`,
      `structs.${r.id}.intra:bad_struct_param`,
    ]);
    expect(codes(section("sets", { sets: "4" }, [[r]], { structs: { [r.id]: { kind: "wave" } as never } }))).toEqual([`structs.${r.id}:unknown_struct`]);
  });

  it("states the load unit once per row: missing_unit and mixed_unit", () => {
    const missing = newRow("ex", { cells: [{ d: "5", l: "60" }, { l: "70" }] });
    expect(codes(section("sets", { sets: "2" }, [[missing]]))).toEqual(["blocks.0.0.cells.0.l:missing_unit", "blocks.0.0.cells.1.l:missing_unit"]);
    const mixed = newRow("ex", { cells: [{ l: "60kg" }, { l: "70%" }] });
    expect(codes(section("sets", { sets: "2" }, [[mixed]]))).toEqual(["blocks.0.0.cells.1.l:mixed_unit"]);
    expect(codes(section("for_time", { rounds: "1" }, [[newRow("ex", { load: "60" })]]))).toEqual(["blocks.0.0.load:missing_unit"]);
    expect(codes(section("for_time", { rounds: "1" }, [[newRow("ex", { load: "βαρύ" })]]))).toEqual([]);
  });

  it("refuses doses that do not read, in cells and plain values", () => {
    expect(codes(section("sets", { sets: "2" }, [[newRow("ex", { cells: [{ d: "lots" }] })]]))).toEqual(["blocks.0.0.cells.0.d:bad_dose"]);
    expect(codes(section("amrap", { dur: "7" }, [[newRow("ex", { dose: "lots" })]]))).toEqual(["blocks.0.0.dose:bad_dose"]);
  });

  it("checks measures: known, once, tempo 4 marks, RPE ≤ 10, numbers", () => {
    const bad = newRow("ex", { extra: ["tempo", "rpe", "dist"], cells: [{ tempo: "31X", rpe: "11", dist: "far" }, { rpe: "+1" }] });
    expect(codes(section("sets", { sets: "2" }, [[bad]]))).toEqual([
      "blocks.0.0.cells.0.tempo:bad_tempo",
      "blocks.0.0.cells.0.rpe:rpe_over_max",
      "blocks.0.0.cells.0.dist:bad_measure_value",
    ]);
    expect(codes(section("sets", { sets: "2" }, [[newRow("ex", { extra: ["rpe"], cells: [{ rpe: "7→11" }] })]]))).toEqual(["blocks.0.0.cells.0.rpe:rpe_over_max"]);
    expect(codes(section("sets", { sets: "2" }, [[newRow("ex", { extra: ["speed" as never, "side", "side"] })]]))).toEqual([
      "blocks.0.0.extra.0:unknown_measure",
      "blocks.0.0.extra.2:duplicate_measure",
    ]);
    expect(codes(section("amrap", { dur: "7" }, [[newRow("ex", { extra: ["rpe"], x: { rpe: "+1" } })]]))).toEqual(["blocks.0.0.x.rpe:bad_measure_value"]);
    expect(measureIssue("rpe", "10", false)).toBeNull();
    expect(measureIssue("hold", "0:30", false)).toBeNull();
  });

  it("checks the score against the flow (and its preset)", () => {
    expect(codes({ ...newSection("sets"), score: "time" })).toEqual(["score:unknown_score"]);
    expect(codes({ ...newSection("emom"), preset: "death_by", score: "rounds_reps" })).toEqual([]);
  });

  it("enforces size bounds and unique ids", () => {
    const blocks = Array.from({ length: PLAN_LIMITS.blocks + 1 }, () => [newRow()]);
    expect(codes(section("for_time", { rounds: "13" }, blocks))).toEqual(["blocks:too_many_blocks"]);
    const rows = Array.from({ length: PLAN_LIMITS.rowsPerBlock + 1 }, () => newRow());
    expect(codes(section("for_time", { rounds: "1" }, [rows]))).toEqual(["blocks.0:too_many_rows"]);
    const cells = Array.from({ length: PLAN_LIMITS.cellsPerRow + 1 }, () => ({ d: "1" }));
    expect(codes(section("sets", { sets: "4" }, [[newRow("ex", { cells })]]))).toEqual(["blocks.0.0.cells:too_many_cells"]);
    const long = "x".repeat(201);
    expect(codes(section("for_time", { rounds: "1" }, [[newRow("ex", { name: long, note: "n".repeat(2001) })]]))).toEqual([
      "blocks.0.0.name:too_long",
      "blocks.0.0.note:note_too_long",
    ]);
    expect(codes({ ...newSection("for_time"), note: "n".repeat(2001), levelNotes: { rx: "n".repeat(2001) } })).toEqual(["note:note_too_long", "levelNotes.rx:note_too_long"]);
    const r = newRow();
    expect(codes(section("for_time", { rounds: "1" }, [[r, { ...r }]]))).toEqual(["blocks.0.1.id:duplicate_id"]);
    expect(codes(section("rest", { dur: "2:00" }, [[newRow()]]))).toEqual(["blocks:blocks_not_allowed"]);
  });
});

describe("paramValid", () => {
  it("reads each kind", () => {
    expect(paramValid({ kind: "time", bare: "smart" }, "90″")).toBe(true);
    expect(paramValid({ kind: "time", bare: "smart" }, "0")).toBe(false);
    expect(paramValid({ kind: "times", bare: "min" }, "3-3-3-4")).toBe(true);
    expect(paramValid({ kind: "count", bare: "smart" }, "0")).toBe(false);
    expect(paramValid({ kind: "range", bare: "smart" }, "3-4")).toBe(true);
    expect(paramValid({ kind: "text", bare: "smart" }, "anything")).toBe(true);
  });
});
