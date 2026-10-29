import { describe, expect, it } from "vitest";
import {
  addBlock,
  applyPreset,
  changeFlow,
  findRow,
  newRow,
  newSection,
  setStructure,
  toggleGroupWithAbove,
  togglePerRound,
} from "./factory";
import { validateSection } from "./validate";
import { PRESETS } from "./catalog";
import type { PlanSection } from "./types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

describe("newRow and newSection", () => {
  it("creates rows with uuids; a rest row rests 30″", () => {
    const r = newRow();
    expect(r).toMatchObject({ kind: "ex", name: "", dose: "", load: "", group: null, cells: [] });
    expect(r.id).toMatch(UUID);
    expect(newRow().id).not.toBe(r.id);
    expect(newRow("rest")).toMatchObject({ kind: "rest", dose: "30″", cells: [{ d: "30″" }] });
    expect(newRow("ex", { name: "Row" }).name).toBe("Row");
  });

  it("creates a valid section of every flow with its defaults", () => {
    const s = newSection("emom");
    expect(s).toMatchObject({ v: 1, flow: "emom", params: { every: "1:00", times: "10" }, score: "none", preset: null, mods: {} });
    expect(s.blocks).toHaveLength(1);
    expect(newSection("rest").blocks).toEqual([]);
    for (const flow of ["sets", "for_time", "amrap", "emom", "intervals", "rest"] as const) expect(validateSection(newSection(flow))).toEqual([]);
  });
});

describe("applyPreset", () => {
  it("applies every preset into a valid section", () => {
    for (const p of PRESETS) {
      const s = applyPreset(newSection("sets"), p.key);
      expect(s.flow).toBe(p.flow);
      expect(s.preset).toBe(p.key);
      expect(validateSection(s)).toEqual([]);
    }
  });

  it("fills Tabata, Death by, Even/odd, EDT, cluster and 'Με διακοπή'", () => {
    expect(applyPreset(newSection("sets"), "tabata").params).toEqual({ work: "20″", off: "10″", rounds: "8" });
    const death = applyPreset(newSection("sets"), "death_by");
    expect(death).toMatchObject({ flow: "emom", params: { every: "1:00", times: "" }, score: "rounds_reps" });
    expect(death.blocks[0][0].dose).toBe("1-2-3…");
    expect(applyPreset(newSection("for_time"), "even_odd").blocks).toHaveLength(2);
    expect(applyPreset(newSection("for_time"), "complex_emom").blocks).toHaveLength(3);
    const edt = applyPreset(newSection("sets"), "edt");
    const [a, b] = edt.blocks[0];
    expect(a.group).toBeTruthy();
    expect(b.group).toBe(a.group);
    expect(edt.structs?.[a.group!]).toEqual({ kind: "superset" });
    const cluster = applyPreset(newSection("for_time"), "cluster");
    expect(cluster.structs?.[cluster.blocks[0][0].id]).toEqual({ kind: "cluster", clusters: "3", intra: "15″" });
    const failure = applyPreset(newSection("for_time"), "to_failure");
    expect(failure.blocks[0][0].cells[0]).toEqual({ d: "max", l: "" });
    const intr = applyPreset(newSection("sets"), "interrupt");
    expect(intr.mods).toEqual({ interrupt: true });
    expect(intr.params.intEvery).toBe("2:00");
    expect(intr.interrupt).toHaveLength(1);
    const hrr = applyPreset(newSection("sets"), "hrr");
    expect(hrr.mods).toEqual({ hr: true });
    expect(hrr.params.hrTarget).toBe("120");
  });

  it("leaves an unknown preset alone and never changes its input", () => {
    const s = newSection("sets");
    const copy = structuredClone(s);
    expect(applyPreset(s, "nope")).toEqual(s);
    applyPreset(s, "edt");
    expect(s).toEqual(copy);
  });
});

describe("changeFlow keeps rows, measures and per-round values", () => {
  const strength = (): PlanSection => {
    const s = newSection("sets");
    s.params.sets = "4";
    s.blocks = [[newRow("ex", { name: "Back Squat", extra: ["tempo", "side"], cells: [{ d: "12", l: "60%", tempo: "31X1" }, { d: "10", l: "+5" }, { d: "8" }, { d: "8" }] }), newRow("rest")]];
    return s;
  };

  it("sets → AMRAP: per set becomes per round, rest rows drop, first set becomes the plain values", () => {
    const s = changeFlow(strength(), "amrap");
    expect(s.blocks[0]).toHaveLength(1);
    const r = s.blocks[0][0];
    expect(r).toMatchObject({ name: "Back Squat", dose: "12", load: "60%", perRound: true, x: { tempo: "31X1" }, extra: ["tempo", "side"] });
    expect(r.cells).toHaveLength(4);
    expect(s.params).toEqual({ dur: "12", rest: "" });
    expect(s.score).toBe("rounds_reps");
  });

  it("AMRAP → sets: plain values become set 1, per round stays per set", () => {
    const s = newSection("amrap");
    s.blocks = [[newRow("ex", { name: "Wall Ball", dose: "20", load: "9kg", x: { height: "300" }, extra: ["height"] }), newRow("ex", { name: "Power Snatch", perRound: true, cells: [{ d: "5", l: "40kg" }, { d: "10", l: "+5kg" }] })]];
    const t = changeFlow(s, "sets");
    expect(t.blocks[0][0]).toMatchObject({ cells: [{ d: "20", l: "9kg", height: "300" }], perRound: false });
    expect(t.blocks[0][1].cells).toEqual([{ d: "5", l: "40kg" }, { d: "10", l: "+5kg" }]);
    expect(t.blocks[0][1].perRound).toBe(false);
    expect(validateSection(t)).toEqual([]);
  });

  it("keeps blocks and resets params, score and add-ons; rest flow drops rows", () => {
    const s = newSection("for_time");
    s.blocks = [[newRow("ex", { name: "Row", dose: "500 m" })], [newRow("ex", { name: "Run", dose: "400 m" })]];
    s.mods = { interrupt: true };
    const e = changeFlow(s, "emom");
    expect(e.blocks.map((b) => b[0].name)).toEqual(["Row", "Run"]);
    expect(e.mods).toEqual({});
    expect(e.interrupt).toEqual([]);
    expect(changeFlow(s, "rest").blocks).toEqual([]);
  });
});

describe("blocks, structures, groups, per round", () => {
  it("adds a block and grows the count to the number of blocks", () => {
    const s = newSection("for_time");
    const { section, row } = addBlock(s);
    expect(section.blocks).toHaveLength(2);
    expect(section.params.rounds).toBe("2");
    expect(findRow(section, row.id)).toMatchObject({ b: 1, i: 0 });
    expect(addBlock(newSection("sets")).section.params.sets).toBe("4");
    expect(addBlock({ ...newSection("emom"), params: { every: "1:00", times: "1" } }).section.params.times).toBe("2");
  });

  it("sets structures: a group takes the next row as partner or adds one; single breaks the group", () => {
    const s = newSection("sets");
    const a = s.blocks[0][0];
    const ss = setStructure(s, 0, a.id, "superset");
    expect(ss.blocks[0]).toHaveLength(2);
    const g = ss.blocks[0][0].group!;
    expect(ss.blocks[0][1].group).toBe(g);
    const cx = setStructure(ss, 0, g, "complex");
    expect(cx.structs?.[g]).toEqual({ kind: "complex" });
    const back = setStructure(cx, 0, g, "drop");
    expect(back.blocks[0].every((r) => !r.group)).toBe(true);
    expect(back.structs?.[g]).toBeUndefined();
    expect(back.structs?.[a.id]).toEqual({ kind: "drop", drops: "2", dropby: "-20%" });
    expect(setStructure(back, 0, a.id, "single").structs?.[a.id]).toBeUndefined();
  });

  it("groups with the row above and ungroups (a lone row leaves its group)", () => {
    const s = newSection("sets");
    s.blocks[0].push(newRow("ex", { name: "B" }));
    const id = s.blocks[0][1].id;
    const g = toggleGroupWithAbove(s, id);
    expect(g.blocks[0][0].group).toBeTruthy();
    expect(g.blocks[0][1].group).toBe(g.blocks[0][0].group);
    const u = toggleGroupWithAbove(g, id);
    expect(u.blocks[0].map((r) => r.group)).toEqual([null, null]);
  });

  it("toggles per round only where a block runs more than once", () => {
    const s = newSection("amrap");
    s.blocks[0][0] = { ...s.blocks[0][0], dose: "15", load: "40kg" };
    const id = s.blocks[0][0].id;
    const on = togglePerRound(s, id);
    expect(on.blocks[0][0]).toMatchObject({ perRound: true, cells: [{ d: "15", l: "40kg" }] });
    on.blocks[0][0].cells[0].d = "5";
    const off = togglePerRound(on, id);
    expect(off.blocks[0][0]).toMatchObject({ perRound: false, dose: "5", load: "40kg" });
    const once = newSection("for_time");
    expect(togglePerRound(once, once.blocks[0][0].id).blocks[0][0].perRound).toBeFalsy();
  });
});
